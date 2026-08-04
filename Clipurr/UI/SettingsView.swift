import AppKit
import SwiftUI

struct SettingsView: View {
    let historyStore: HistoryStore

    @State private var preferredLanguage = AppSettings.preferredLanguage
    @State private var historyContentMode = AppSettings.historyContentMode
    @State private var hideCopiedContentMode = AppSettings.hideCopiedContentMode
    @State private var historyClearInterval = AppSettings.historyClearInterval
    @State private var encryptHistory = AppSettings.encryptHistory
    @State private var moveToTopOnPaste = AppSettings.moveToTopOnPaste
    @State private var historyLimitText = String(AppSettings.historyLimit)
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var accessibilityGranted = AccessibilityService.isTrusted
    @State private var launchAtLoginError: String?
    @State private var showRestartAlert = false
    @FocusState private var isHistoryLimitFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.settingsSections) {
                generalSection
                historySection
                permissionsSection
            }
            .padding(ClipurrTheme.Spacing.settingsOuter)
        }
        .frame(width: ClipurrTheme.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .onAppear {
            refreshPermissions()
            encryptHistory = AppSettings.encryptHistory
            moveToTopOnPaste = AppSettings.moveToTopOnPaste
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshPermissions()
            encryptHistory = AppSettings.encryptHistory
            moveToTopOnPaste = AppSettings.moveToTopOnPaste
        }
        .alert(
            String(localized: "Couldn’t update Launch at Login"),
            isPresented: Binding(
                get: { launchAtLoginError != nil },
                set: { if !$0 { launchAtLoginError = nil } }
            )
        ) {
            Button(String(localized: "Open Settings")) {
                LaunchAtLoginService.openLoginItemsSettings()
            }
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(launchAtLoginError ?? "")
        }
        .alert(
            String(localized: "Restart required"),
            isPresented: $showRestartAlert
        ) {
            Button(String(localized: "Restart Clipurr")) {
                Localization.relaunchApplication()
            }
            Button(String(localized: "Later"), role: .cancel) {}
        } message: {
            Text(String(localized: "Clipurr will restart to apply the new language."))
        }
    }

    private var header: some View {
        HStack(spacing: ClipurrTheme.Spacing.rowContent) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ClipurrTheme.Radius.icon,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Settings"))
                    .font(.title3.weight(.semibold))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Clipurr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppVersion.short)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: ClipurrTheme.Spacing.rowContent)

            Text(verbatim: "Clip → Purr → Paste")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, ClipurrTheme.Spacing.settingsOuter)
        .padding(.vertical, ClipurrTheme.Spacing.headerHorizontal)
    }

    private var generalSection: some View {
        SettingsSection(title: String(localized: "General")) {
            SettingsRow(
                title: String(localized: "Language"),
                subtitle: String(localized: "Interface language")
            ) {
                Picker("", selection: $preferredLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: preferredLanguage) { _, language in
                    AppSettings.preferredLanguage = language
                    Localization.applyPreferredLanguage()
                    showRestartAlert = true
                }
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Launch at Login"),
                subtitle: String(localized: "Start Clipurr when you log in to this Mac")
            ) {
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: String(localized: "History")) {
            SettingsRow(
                title: String(localized: "Limit"),
                subtitle: String(localized: "How many items to keep")
            ) {
                TextField("", text: $historyLimitText)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(
                            cornerRadius: ClipurrTheme.Radius.control,
                            style: .continuous
                        )
                        .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ClipurrTheme.Radius.control,
                            style: .continuous
                        )
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                    .focusEffectDisabled()
                    .focused($isHistoryLimitFocused)
                    .onChange(of: historyLimitText) { _, newValue in
                        sanitizeHistoryLimitText(newValue)
                    }
                    .onChange(of: isHistoryLimitFocused) { _, focused in
                        if !focused {
                            commitHistoryLimit()
                        }
                    }
                    .onSubmit {
                        commitHistoryLimit()
                        isHistoryLimitFocused = false
                    }
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Store"),
                subtitle: String(localized: "What Clipurr saves from the clipboard"),
                footnote: historyContentMode.storesFiles
                    ? String(localized: "Only file paths are stored — don’t move files before pasting.")
                    : nil,
                alignment: .top
            ) {
                Picker("", selection: $historyContentMode.animation(.easeInOut(duration: 0.22))) {
                    ForEach(HistoryContentMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: historyContentMode) { _, mode in
                    applyHistoryContentMode(mode)
                }
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Hide history content"),
                subtitle: String(localized: "Blur unfocused rows.\nPaste via ⇧⌃⌘V is always blurred.")
            ) {
                Toggle("", isOn: alwaysHideContentBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Encrypt history"),
                subtitle: String(localized: "Seal clipboard data on disk with a local key")
            ) {
                Toggle("", isOn: encryptHistoryBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Move to top on paste"),
                subtitle: String(localized: "Pasted items become newest when you reopen history")
            ) {
                Toggle("", isOn: moveToTopOnPasteBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Clear history"),
                subtitle: String(localized: "Automatically erase clipboard history")
            ) {
                Picker("", selection: $historyClearInterval) {
                    ForEach(HistoryClearInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: historyClearInterval) { _, interval in
                    AppSettings.historyClearInterval = interval
                }
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: String(localized: "Permissions")) {
            PermissionRow(
                title: String(localized: "Accessibility"),
                subtitle: String(localized: "Required to paste into other apps after you pick an item"),
                isGranted: accessibilityGranted,
                actionTitle: String(localized: "Open Settings")
            ) {
                requestAccessibility()
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                if LaunchAtLoginService.setEnabled(enabled) {
                    launchAtLogin = LaunchAtLoginService.isEnabled
                } else {
                    launchAtLogin = LaunchAtLoginService.isEnabled
                    if enabled {
                        launchAtLoginError = String(localized: """
                        macOS may need approval in System Settings → General → Login Items. \
                        Allow Clipurr there, then try again.
                        """)
                    }
                }
            }
        )
    }

    private var alwaysHideContentBinding: Binding<Bool> {
        Binding(
            get: { hideCopiedContentMode == .always },
            set: { alwaysHide in
                let mode: HideCopiedContentMode = alwaysHide ? .always : .securePasteOnly
                hideCopiedContentMode = mode
                AppSettings.hideCopiedContentMode = mode
            }
        )
    }

    private var encryptHistoryBinding: Binding<Bool> {
        Binding(
            get: { encryptHistory },
            set: { enabled in
                encryptHistory = enabled
                historyStore.setEncryptionEnabled(enabled)
            }
        )
    }

    private var moveToTopOnPasteBinding: Binding<Bool> {
        Binding(
            get: { moveToTopOnPaste },
            set: { enabled in
                moveToTopOnPaste = enabled
                AppSettings.moveToTopOnPaste = enabled
            }
        )
    }

    private func sanitizeHistoryLimitText(_ newValue: String) {
        var digits = String(newValue.filter(\.isNumber))
        if let value = Int(digits), value > AppSettings.maxHistoryLimit {
            digits = String(AppSettings.maxHistoryLimit)
        }
        if digits != newValue {
            historyLimitText = digits
        }
    }

    private func commitHistoryLimit() {
        let parsed = Int(historyLimitText.filter(\.isNumber)) ?? AppSettings.defaultHistoryLimit
        AppSettings.historyLimit = parsed
        historyLimitText = String(AppSettings.historyLimit)
        historyStore.pruneToCurrentLimit()
    }

    private func applyHistoryContentMode(_ mode: HistoryContentMode) {
        AppSettings.historyContentMode = mode
        if !mode.storesImages {
            historyStore.removeAll(ofKind: .image)
        }
        if !mode.storesFiles {
            historyStore.removeAll(ofKind: .files)
        }
    }

    private func refreshPermissions() {
        let accessibility = AccessibilityService.isTrusted
        let login = LaunchAtLoginService.isEnabled
        if accessibilityGranted != accessibility {
            accessibilityGranted = accessibility
        }
        if launchAtLogin != login {
            launchAtLogin = login
        }
    }

    private func requestAccessibility() {
        AccessibilityService.openSystemSettings()
        refreshPermissions()
    }
}
