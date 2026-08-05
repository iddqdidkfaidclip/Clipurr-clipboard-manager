import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @State private var appearance = AppearanceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.sectionInner) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appearance.palette.secondaryLabel)
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background {
                let shape = RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.section,
                    style: .continuous
                )
                shape.fill(appearance.palette.elevated)
                // Soft accent wash so section cards track the chosen accent.
                shape.fill(appearance.accentColor.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.section,
                    style: .continuous
                )
                .strokeBorder(appearance.palette.border.opacity(0.9), lineWidth: 1)
            }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    var footnote: String? = nil
    var alignment: VerticalAlignment = .center
    @ViewBuilder let trailing: Trailing

    @State private var appearance = AppearanceStore.shared

    var body: some View {
        HStack(alignment: alignment, spacing: ClipurrTheme.Spacing.rowContent) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClipurrTheme.rowTitleFont)
                    .foregroundStyle(appearance.palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appearance.palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(appearance.palette.secondaryLabel.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.22), value: footnote)

            trailing
                .padding(.top, alignment == .top ? 2 : 0)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.statusHorizontal)
        .padding(.vertical, ClipurrTheme.Spacing.rowContent)
    }
}

/// Menu-style value control with theme-absolute label colors (avoids AppKit
/// popup title inheriting system dark text on a light Clipurr canvas).
struct SettingsMenuPicker<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var appearance = AppearanceStore.shared

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                content()
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(appearance.palette.label)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.control,
                    style: .continuous
                )
                .fill(appearance.palette.control)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.control,
                    style: .continuous
                )
                .strokeBorder(appearance.palette.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityValue(title)
    }
}

struct PermissionRow: View {
    let title: String
    let subtitle: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    @State private var appearance = AppearanceStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: ClipurrTheme.Spacing.rowContent) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isGranted ? ClipurrTheme.success : ClipurrTheme.danger)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClipurrTheme.rowTitleFont)
                    .foregroundStyle(appearance.palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appearance.palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isGranted {
                    Text(String(localized: "Granted"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(appearance.palette.secondaryLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(appearance.palette.border.opacity(0.35), in: Capsule())
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .fixedSize()
                        .settingsControlLabel(appearance)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.statusHorizontal)
        .padding(.vertical, ClipurrTheme.Spacing.rowContent)
    }
}
