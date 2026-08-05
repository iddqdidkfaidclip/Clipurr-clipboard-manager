import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var historyStore: HistoryStore
    @Bindable var panelState: HistoryPanelState
    @Bindable var circularWindow: CircularHistoryWindow
    let onSelect: (ClipboardEntry) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var appearance = AppearanceStore.shared
    @State private var listViewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if historyStore.entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "Clipboard is empty"),
                    systemImage: "clipboard",
                    description: Text(emptyHistoryDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                historyList
            }

            if let statusMessage = panelState.statusMessage {
                Divider()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ClipurrTheme.Spacing.statusHorizontal)
                    .padding(.vertical, 9)
            }
        }
        .frame(
            width: ClipurrTheme.historyPanelSize(for: panelState.panelSize).width,
            height: ClipurrTheme.historyPanelSize(for: panelState.panelSize).height
        )
        .background {
            HistoryPanelBackground(
                effect: appearance.backgroundEffect,
                canvas: appearance.palette.canvas,
                tintAlpha: appearance.historyTintAlpha,
                border: appearance.palette.border,
                shape: Self.panelShape
            )
        }
        .clipShape(Self.panelShape)
        .clipurrAppearance(appearance)
    }

    private static let panelShape = RoundedRectangle(
        cornerRadius: ClipurrTheme.Radius.row,
        style: .continuous
    )

    private var emptyHistoryDescription: String {
        switch panelState.historyContentMode {
        case .textOnly:
            String(localized: "Copy text to see it here.")
        case .textAndImages:
            String(localized: "Copy text or an image to see them here.")
        case .textImagesAndFiles:
            String(localized: "Copy text, an image, or files to see them here.")
        }
    }

    private var header: some View {
        HStack(spacing: ClipurrTheme.Spacing.headerIcon) {
            TrafficLightCloseButton(action: onClose)

            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)

            Text("Clipurr")
                .font(.headline)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Settings…"))
            .accessibilityLabel(String(localized: "Settings…"))

            Spacer()
            Text(String(localized: "↑↓ Select  ·  ↩ Paste  ·  esc Close"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.headerHorizontal)
        .frame(height: ClipurrTheme.historyHeaderHeight)
    }

    private static let listPadding: CGFloat = 10
    /// preview (42) + vertical padding (9×2); title can grow a bit, spacing is separate.
    private static let estimatedRowHeight: CGFloat = 60

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ClipurrTheme.Spacing.rowList) {
                    ForEach(circularWindow.tokens) { token in
                        if let entry = circularWindow.entry(at: token, in: historyStore.entries) {
                            Button {
                                panelState.select(token: token, entry: entry)
                                onSelect(entry)
                            } label: {
                                HistoryRowView(
                                    entry: entry,
                                    isSelected: panelState.selectedTokenID == token.id,
                                    blurUnfocusedContent: panelState.shouldHideCopiedContent,
                                    relativeTo: panelState.openedAt,
                                    horizontalInset: Self.listPadding
                                )
                            }
                            .buttonStyle(.plain)
                            .id(token.id)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Keep rows off the header/footer edges when scrolled to .top / .bottom.
            .contentMargins(.vertical, Self.listPadding, for: .scrollContent)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: HistoryListViewportHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(HistoryListViewportHeightKey.self) { height in
                listViewportHeight = height
            }
            .onAppear {
                prepareListOpen(proxy: proxy)
            }
            .onChange(of: panelState.openedAt) { _, _ in
                prepareListOpen(proxy: proxy)
            }
            .onChange(of: panelState.selectedTokenID) { _, _ in
                guard panelState.animateSelectionScroll else { return }
                scrollToSelection(proxy: proxy)
            }
        }
    }

    private func prepareListOpen(proxy: ScrollViewProxy) {
        // LazyVStack needs a layout pass before scrollTo is reliable.
        DispatchQueue.main.async {
            scrollToListTop(proxy: proxy)
            DispatchQueue.main.async {
                scrollToListTop(proxy: proxy)
            }
        }
    }

    private func scrollToListTop(proxy: ScrollViewProxy) {
        if let topID = circularWindow.listTopTokenID {
            proxy.scrollTo(topID, anchor: .top)
        }
    }

    private func scrollToSelection(proxy: ScrollViewProxy) {
        guard let scrollID = panelState.selectedTokenID else { return }
        let index = circularWindow.tokens.firstIndex { $0.id == scrollID } ?? 0
        let rowStride = Self.estimatedRowHeight + ClipurrTheme.Spacing.rowList
        // Rows that still fit in the upper half stay put; past that, keep selection centered.
        let centerIndex = max(
            Int(((listViewportHeight / 2) - Self.listPadding) / rowStride),
            0
        )

        withAnimation(.easeOut(duration: 0.12)) {
            if index <= centerIndex {
                // Pin to top so ↓ walks the highlight toward mid-viewport.
                scrollToListTop(proxy: proxy)
            } else {
                proxy.scrollTo(scrollID, anchor: .center)
            }
        }
    }
}

private enum HistoryListViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TrafficLightCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(ClipurrTheme.trafficLightClose)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    }

                if isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close"))
        .onHover { isHovered = $0 }
        .accessibilityLabel(String(localized: "Close"))
    }
}

private struct HistoryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let blurUnfocusedContent: Bool
    let relativeTo: Date
    var horizontalInset: CGFloat = 0

    @State private var appearance = AppearanceStore.shared
    @State private var filesAreAvailable = true

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var shouldBlur: Bool {
        blurUnfocusedContent && !isSelected
    }

    private var relativeTimestamp: String {
        let formatted = Self.relativeFormatter.localizedString(
            for: entry.createdAt,
            relativeTo: relativeTo
        )
        // Abbreviated style uses a leading "-" / "+" for past/future (e.g. "-5 мин").
        // Clipboard history is always past, so drop the sign for a cleaner label.
        if formatted.hasPrefix("-") || formatted.hasPrefix("+") {
            return String(formatted.dropFirst())
        }
        return formatted
    }

    var body: some View {
        HStack(spacing: ClipurrTheme.Spacing.rowContent) {
            preview
                .frame(width: ClipurrTheme.previewSize, height: ClipurrTheme.previewSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.plaintextTitle())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .font(ClipurrTheme.rowTitleFont)
                    .foregroundStyle(.primary)
                    .blur(radius: shouldBlur ? ClipurrTheme.contentBlurRadius : 0)
                HStack(spacing: 5) {
                    Text(entry.kind.displayName)
                        .fixedSize()
                    Text(verbatim: "·")
                        .fixedSize()
                    Text(entry.plaintextSubtitle())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .blur(radius: shouldBlur ? ClipurrTheme.contentBlurRadius : 0)
                    if entry.kind == .files, !filesAreAvailable {
                        Text(String(localized: "· Missing"))
                            .foregroundStyle(ClipurrTheme.danger)
                            .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeTimestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
                .padding(.leading, ClipurrTheme.Spacing.sectionInner)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.rowContent + horizontalInset)
        .padding(.vertical, 9)
        .background(
            Rectangle()
                .fill(isSelected ? appearance.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(appearance.accentColor.opacity(0.65), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .onAppear(perform: refreshFileAvailability)
        .onChange(of: entry.id) { _, _ in
            refreshFileAvailability()
        }
    }

    @ViewBuilder
    private var preview: some View {
        let shape = RoundedRectangle(
            cornerRadius: ClipurrTheme.Radius.preview,
            style: .continuous
        )

        if entry.kind == .image,
           let thumbnailData = entry.plaintextThumbnailData(),
           let image = NSImage(data: thumbnailData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: shouldBlur ? ClipurrTheme.contentBlurRadius : 0)
                .background(.quaternary)
                .clipShape(shape)
                .overlay {
                    if shouldBlur {
                        shape.fill(.ultraThinMaterial.opacity(0.35))
                    }
                }
        } else {
            Image(systemName: entry.kind.systemImage)
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary, in: shape)
        }
    }

    private func refreshFileAvailability() {
        guard entry.kind == .files else {
            filesAreAvailable = true
            return
        }
        filesAreAvailable = ClipboardPayloadCodec.filesAreAvailable(
            payload: entry.plaintextPayload()
        )
    }
}
