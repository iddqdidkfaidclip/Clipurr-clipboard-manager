import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.sectionInner) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.section,
                    style: .continuous
                )
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClipurrTheme.Radius.section,
                    style: .continuous
                )
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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

    var body: some View {
        HStack(alignment: alignment, spacing: ClipurrTheme.Spacing.rowContent) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClipurrTheme.rowTitleFont)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

struct PermissionRow: View {
    let title: String
    let subtitle: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

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
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isGranted {
                    Text(String(localized: "Granted"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .fixedSize()
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.statusHorizontal)
        .padding(.vertical, ClipurrTheme.Spacing.rowContent)
    }
}
