import AppKit
import SwiftUI

struct AboutView: View {
    @State private var appearance = AppearanceStore.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ClipurrTheme.Spacing.rowContent) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ClipurrTheme.Radius.section,
                            style: .continuous
                        )
                    )

                VStack(spacing: 8) {
                    Text("Clipurr")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(appearance.palette.label)
                    Text(AppVersion.short)
                        .font(.body)
                        .foregroundStyle(appearance.palette.secondaryLabel)
                    Button(String(localized: "Check for Updates…")) {
                        UpdateService.shared.checkForUpdates(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .settingsControlLabel(appearance)
                }

                Text(String(localized: """
                First local clipboard history for macOS with shoulder-surfing protection.
                Clip → Purr → Paste
                """))
                .font(.callout)
                .foregroundStyle(appearance.palette.secondaryLabel)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ClipurrTheme.Spacing.settingsOuter)
            .padding(.top, 28)
            .padding(.bottom, ClipurrTheme.Spacing.settingsOuter)

            Divider()

            VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.sectionInner) {
                Text(String(localized: "Shortcuts"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appearance.palette.secondaryLabel)

                shortcutRow(
                    keys: "⇧⌘V",
                    title: String(localized: "Open History"),
                    detail: String(localized: "Browse clipboard history and paste")
                )
                shortcutRow(
                    keys: "⇧⌃⌘V",
                    title: String(localized: "Secure Paste"),
                    detail: String(localized: "Same history with blurred previews")
                )
            }
            .padding(ClipurrTheme.Spacing.settingsOuter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(appearance.palette.canvas)
        .clipurrAppearance(appearance)
    }

    private func shortcutRow(keys: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: ClipurrTheme.Spacing.rowContent) {
            Text(keys)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(appearance.palette.label)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(appearance.palette.label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(appearance.palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
