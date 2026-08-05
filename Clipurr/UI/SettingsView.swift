import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case history
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .history: String(localized: "History")
        case .appearance: String(localized: "Appearance")
        }
    }
}

struct SettingsView: View {
    let historyStore: HistoryStore
    /// Called when intrinsic content height should drive the window frame.
    /// `animated` softens tab switches; theme changes can stay snappier.
    var onContentChange: ((_ animated: Bool) -> Void)? = nil

    @State private var selectedTab: SettingsTab = .general
    @State private var preferredLanguage = AppSettings.preferredLanguage
    @State private var historyContentMode = AppSettings.historyContentMode
    @State private var hideCopiedContentMode = AppSettings.hideCopiedContentMode
    @State private var historyClearInterval = AppSettings.historyClearInterval
    @State private var encryptHistory = AppSettings.encryptHistory
    @State private var moveToTopOnPaste = AppSettings.moveToTopOnPaste
    @State private var panelSize = AppSettings.panelSize
    @State private var panelAnchor = AppSettings.panelAnchor
    @State private var historyLimitText = String(AppSettings.historyLimit)
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var accessibilityGranted = AccessibilityService.isTrusted
    @State private var launchAtLoginError: String?
    @State private var showRestartAlert = false
    @State private var appearance = AppearanceStore.shared
    @State private var isPickingCustomAccent = false
    @FocusState private var isHistoryLimitFocused: Bool

    private static let tabAnimation = Animation.easeInOut(duration: 0.28)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: selectedTabBinding) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .environment(\.colorScheme, appearance.colorScheme)
            .padding(.horizontal, ClipurrTheme.Spacing.settingsOuter)
            .padding(.top, ClipurrTheme.Spacing.settingsOuter)
            .padding(.bottom, ClipurrTheme.Spacing.sectionInner)

            // Only the settings body crossfades — header + tabs stay put.
            ZStack(alignment: .top) {
                tabBody
                    .id(selectedTab)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 5)),
                            removal: .opacity
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .clipped()
            .padding(.horizontal, ClipurrTheme.Spacing.settingsOuter)
            .padding(.bottom, ClipurrTheme.Spacing.settingsOuter)
        }
        .frame(width: ClipurrTheme.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(appearance.palette.canvas)
        .clipurrAppearance(appearance)
        .onAppear {
            refreshPermissions()
            encryptHistory = AppSettings.encryptHistory
            moveToTopOnPaste = AppSettings.moveToTopOnPaste
            panelSize = AppSettings.panelSize
            panelAnchor = AppSettings.panelAnchor
            appearance.applyToOpenWindows()
        }
        .onChange(of: selectedTab) { _, _ in
            requestContentRefit(animated: true)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshPermissions()
            encryptHistory = AppSettings.encryptHistory
            moveToTopOnPaste = AppSettings.moveToTopOnPaste
            panelSize = AppSettings.panelSize
            panelAnchor = AppSettings.panelAnchor
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

    private func requestContentRefit(animated: Bool = false) {
        // Wait one turn so SwiftUI commits the new tab’s intrinsic size first.
        DispatchQueue.main.async {
            onContentChange?(animated)
        }
    }

    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard tab != selectedTab else { return }
                withAnimation(Self.tabAnimation) {
                    selectedTab = tab
                }
            }
        )
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .general:
            VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.settingsSections) {
                generalSection
                permissionsSection
            }
        case .history:
            historySection
        case .appearance:
            appearanceSection
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
                    .foregroundStyle(appearance.palette.label)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Clipurr")
                        .font(.caption)
                        .foregroundStyle(appearance.palette.secondaryLabel)
                    Text(AppVersion.short)
                        .font(.caption2)
                        .foregroundStyle(appearance.palette.secondaryLabel.opacity(0.85))
                }
            }

            Spacer(minLength: ClipurrTheme.Spacing.rowContent)

            Text(verbatim: "Clip → Purr → Paste")
                .font(.caption)
                .foregroundStyle(appearance.palette.secondaryLabel)
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
                SettingsMenuPicker(
                    selection: $preferredLanguage,
                    title: preferredLanguage.displayName
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
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

            Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

            SettingsRow(
                title: String(localized: "Encrypt data on disk"),
                subtitle: String(localized: "Seal clipboard data on disk with a local key")
            ) {
                Toggle("", isOn: encryptHistoryBinding)
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
                    .foregroundStyle(appearance.palette.label)
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
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
                    .focusEffectDisabled()
                    .focused($isHistoryLimitFocused)
                    .environment(\.colorScheme, appearance.colorScheme)
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
                SettingsMenuPicker(
                    selection: $historyContentMode.animation(.easeInOut(duration: 0.22)),
                    title: historyContentMode.displayName
                ) {
                    ForEach(HistoryContentMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
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
                SettingsMenuPicker(
                    selection: $historyClearInterval,
                    title: historyClearInterval.displayName
                ) {
                    ForEach(HistoryClearInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
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

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: ClipurrTheme.Spacing.settingsSections) {
            SettingsSection(title: String(localized: "Theme")) {
                SettingsRow(
                    title: String(localized: "Appearance"),
                    subtitle: String(localized: "Black, soft black, or light window surfaces")
                ) {
                    SettingsMenuPicker(
                        selection: themeBinding,
                        title: appearance.theme.displayName
                    ) {
                        ForEach(AppearanceTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                }
            }

            SettingsSection(title: String(localized: "Accent")) {
                SettingsRow(
                    title: String(localized: "Accent color"),
                    subtitle: String(localized: "Selection rings and settings section tint"),
                    alignment: .top
                ) {
                    accentSwatches
                }
            }

            SettingsSection(title: String(localized: "History window")) {
                SettingsRow(
                    title: String(localized: "Panel size"),
                    subtitle: String(localized: "History window size")
                ) {
                    SettingsMenuPicker(
                        selection: $panelSize,
                        title: panelSize.displayName
                    ) {
                        ForEach(PanelSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .onChange(of: panelSize) { _, size in
                        AppSettings.panelSize = size
                    }
                }

                Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

                SettingsRow(
                    title: String(localized: "Stick to"),
                    subtitle: String(localized: "Where the history window appears")
                ) {
                    SettingsMenuPicker(
                        selection: panelAnchorBinding,
                        title: panelAnchor.displayName
                    ) {
                        ForEach(PanelAnchor.allCases) { anchor in
                            Text(anchor.displayName).tag(anchor)
                        }
                    }
                }

                Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

                SettingsRow(
                    title: String(localized: "Background effect"),
                    subtitle: String(localized: "Blur or glass behind the history panel")
                ) {
                    SettingsMenuPicker(
                        selection: backgroundEffectBinding,
                        title: appearance.backgroundEffect.displayName
                    ) {
                        ForEach(HistoryBackgroundEffect.allCases) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                }

                Divider().padding(.leading, ClipurrTheme.Spacing.statusHorizontal)

                SettingsRow(
                    title: String(localized: "Background opacity"),
                    subtitle: String(localized: "Tint strength over the backdrop (history only)")
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: backgroundOpacityBinding,
                            in: Double(AppSettings.minBackgroundOpacity)
                                ... Double(AppSettings.maxBackgroundOpacity)
                        )
                        .controlSize(.small)
                        .frame(width: 140)
                        .focusEffectDisabled()
                        Text("\(appearance.backgroundOpacity)%")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(appearance.palette.secondaryLabel)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var accentSwatches: some View {
        HStack(spacing: 8) {
            ForEach(AccentColorChoice.presets) { choice in
                Button {
                    isPickingCustomAccent = false
                    appearance.setAccent(choice)
                } label: {
                    ZStack {
                        Circle()
                            .fill(choice.swiftUIColor)
                            .frame(width: 22, height: 22)
                        if appearance.accent == choice {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(accentCheckmarkColor(for: choice.swiftUIColor))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(choice.displayName)
                .accessibilityLabel(choice.displayName)
                .accessibilityAddTraits(appearance.accent == choice ? .isSelected : [])
            }

            customAccentSwatch
        }
    }

    /// Rainbow ring that opens the system color wheel for a custom accent.
    private var customAccentSwatch: some View {
        Button(action: openCustomColorWheel) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                .red, .orange, .yellow, .green,
                                .mint, .blue, .purple, .pink, .red
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .fill(
                                appearance.accent == .custom
                                    ? appearance.customAccent
                                    : appearance.palette.elevated
                            )
                            .padding(5)
                    }

                if appearance.accent == .custom {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accentCheckmarkColor(for: appearance.customAccent))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Custom"))
        .accessibilityLabel(String(localized: "Custom"))
        .accessibilityAddTraits(appearance.accent == .custom ? .isSelected : [])
        .onReceive(
            NotificationCenter.default.publisher(for: NSColorPanel.colorDidChangeNotification)
        ) { notification in
            guard isPickingCustomAccent else { return }
            guard let panel = notification.object as? NSColorPanel else { return }
            appearance.setCustomAccent(Color(nsColor: panel.color))
        }
    }

    private func openCustomColorWheel() {
        isPickingCustomAccent = true
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.color = NSColor(appearance.customAccent)
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Selecting on the wheel writes through colorDidChangeNotification.
        if appearance.accent != .custom {
            appearance.setCustomAccent(appearance.customAccent)
        }
    }

    private func accentCheckmarkColor(for color: Color) -> Color {
        color.isAccentCheckmarkDark
            ? Color.black.opacity(0.65)
            : Color.white.opacity(0.92)
    }

    private var themeBinding: Binding<AppearanceTheme> {
        Binding(
            get: { appearance.theme },
            set: { newValue in
                appearance.setTheme(newValue)
                requestContentRefit(animated: true)
            }
        )
    }

    private var backgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(appearance.backgroundOpacity) },
            set: { appearance.setBackgroundOpacity(Int($0.rounded())) }
        )
    }

    private var backgroundEffectBinding: Binding<HistoryBackgroundEffect> {
        Binding(
            get: { appearance.backgroundEffect },
            set: { appearance.setBackgroundEffect($0) }
        )
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

    private var panelAnchorBinding: Binding<PanelAnchor> {
        Binding(
            get: { panelAnchor },
            set: { newValue in
                panelAnchor = newValue
                AppSettings.panelAnchor = newValue
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
