import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var historyStore: HistoryStore
    @Bindable var panelState: HistoryPanelState
    let onSelect: (ClipboardEntry) -> Void
    let onClose: () -> Void

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
            width: ClipurrTheme.historyPanelSize.width,
            height: ClipurrTheme.historyPanelSize.height
        )
        .background(.regularMaterial)
    }

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

            Spacer()
            Text(String(localized: "↑↓ Select  ·  ↩ Paste  ·  esc Close"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.headerHorizontal)
        .frame(height: ClipurrTheme.historyHeaderHeight)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ClipurrTheme.Spacing.rowList) {
                    ForEach(historyStore.entries, id: \.id) { entry in
                        Button {
                            panelState.selectedID = entry.id
                            onSelect(entry)
                        } label: {
                            HistoryRowView(
                                entry: entry,
                                isSelected: panelState.selectedID == entry.id,
                                blurUnfocusedContent: panelState.shouldHideCopiedContent,
                                relativeTo: panelState.openedAt
                            )
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: panelState.selectedID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
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
                    .font(ClipurrTheme.rowTitleFont)
                    .foregroundStyle(.primary)
                    .blur(radius: shouldBlur ? ClipurrTheme.contentBlurRadius : 0)
                HStack(spacing: 5) {
                    Text(entry.kind.displayName)
                    Text(verbatim: "·")
                    Text(entry.plaintextSubtitle())
                        .blur(radius: shouldBlur ? ClipurrTheme.contentBlurRadius : 0)
                    if entry.kind == .files, !filesAreAvailable {
                        Text(String(localized: "· Missing"))
                            .foregroundStyle(ClipurrTheme.danger)
                    }
                }
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: ClipurrTheme.Spacing.sectionInner)
            Text(relativeTimestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.rowContent)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: ClipurrTheme.Radius.row, style: .continuous)
                .fill(isSelected ? ClipurrTheme.selectionHighlight.opacity(0.18) : Color.clear)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: ClipurrTheme.Radius.row, style: .continuous)
                    .stroke(ClipurrTheme.selectionHighlight.opacity(0.65), lineWidth: 1)
            }
        }
        .contentShape(
            RoundedRectangle(cornerRadius: ClipurrTheme.Radius.row, style: .continuous)
        )
        .animation(.easeOut(duration: 0.16), value: isSelected)
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
