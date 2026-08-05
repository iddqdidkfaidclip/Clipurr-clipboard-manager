import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    private var modelContainer: ModelContainer!
    private var historyStore: HistoryStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var pasteService: PasteService!
    private var panelController: HistoryPanelController!
    private var hotKeyManager: HotKeyManager?
    private var settingsWindowController: SettingsWindowController!
    private var aboutWindowController: AboutWindowController!
    private var historyClearScheduler: HistoryClearScheduler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Localization.applyPreferredLanguage()
        NSApp.setActivationPolicy(.accessory)
        // Start Sparkle early so automatic update checks are live.
        _ = UpdateService.shared
        configureServices()
        configureStatusItem()
        clipboardMonitor.start()
        historyClearScheduler.start()
        configureHotKey()
        showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        historyClearScheduler.stop()
        clipboardMonitor.stop()
    }

    private func configureServices() {
        do {
            let schema = Schema([ClipboardEntry.self])
            let configuration = ModelConfiguration(
                "ClipurrHistory",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to create Clipurr history store: \(error)")
        }

        historyStore = HistoryStore(container: modelContainer)
        clipboardMonitor = ClipboardMonitor(historyStore: historyStore)
        pasteService = PasteService(monitor: clipboardMonitor)
        settingsWindowController = SettingsWindowController(historyStore: historyStore)
        aboutWindowController = AboutWindowController()
        panelController = HistoryPanelController(
            historyStore: historyStore,
            pasteService: pasteService,
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show()
            }
        )
        historyClearScheduler = HistoryClearScheduler(historyStore: historyStore) { [weak self] in
            self?.panelController.hide()
        }
        // Persist any legacy blur-toggle migration before views read AppStorage.
        _ = AppSettings.hideCopiedContentMode
        AppearanceStore.shared.applyToOpenWindows()
    }

    private func configureHotKey() {
        do {
            let manager = try HotKeyManager()
            manager.onPressed = { [weak self] action in
                switch action {
                case .paste:
                    self?.panelController.toggle(securePaste: false)
                case .securePaste:
                    self?.panelController.toggle(securePaste: true)
                }
            }
            hotKeyManager = manager
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Hotkey unavailable")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menuBarImage = NSImage(named: "MenuBarIcon")
            ?? NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Clipurr"
            )
        menuBarImage?.isTemplate = true
        // Asset catalog points are 18×18; pin size so Retina templates aren't
        // drawn oversized and optically squashed in the status item.
        menuBarImage?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = menuBarImage
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "About Clipurr"),
            action: #selector(openAbout),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())

        let openHistoryItem = NSMenuItem(
            title: String(localized: "Open History"),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        openHistoryItem.target = self
        openHistoryItem.image = NSImage(
            systemSymbolName: "clock",
            accessibilityDescription: String(localized: "Open History")
        )
        menu.addItem(openHistoryItem)

        let clearHistoryItem = NSMenuItem(
            title: String(localized: "Clear History…"),
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearHistoryItem.target = self
        clearHistoryItem.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: String(localized: "Clear History")
        )
        menu.addItem(clearHistoryItem)
        menu.addItem(.separator())

        let pasteHint = NSMenuItem(
            title: String(localized: "Paste: ⇧⌘V"),
            action: nil,
            keyEquivalent: ""
        )
        pasteHint.isEnabled = false
        menu.addItem(pasteHint)

        let securePasteHint = NSMenuItem(
            title: String(localized: "Paste Secretly: ⇧⌃⌘V"),
            action: nil,
            keyEquivalent: ""
        )
        securePasteHint.isEnabled = false
        menu.addItem(securePasteHint)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Quit Clipurr"),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self
        statusItem.menu = menu
    }

    private func showOnboardingIfNeeded() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            self.showAccessibilityOnboardingIfNeeded()
            self.enableLaunchAtLoginByDefaultIfNeeded()
        }
    }

    private func showAccessibilityOnboardingIfNeeded() {
        let key = "didShowAccessibilityOnboarding"
        guard !AccessibilityService.canAutomatePaste,
              !UserDefaults.standard.bool(forKey: key) else {
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        // Appear in the Accessibility list without opening System Settings yet.
        AccessibilityService.registerInAccessibilityList()

        let alert = NSAlert()
        alert.messageText = String(localized: "Enable automatic paste")
        alert.informativeText = String(localized: """
        Clipurr needs Accessibility access to send Cmd+V after you choose an item. \
        Clipboard capture and history remain local on this Mac.
        """)
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityService.openSystemSettings()
        }
    }

    private func enableLaunchAtLoginByDefaultIfNeeded() {
        guard !AppSettings.didAskLaunchAtLogin else { return }
        AppSettings.didAskLaunchAtLogin = true
        guard !LaunchAtLoginService.isEnabled else { return }
        // Silent attempt only — never jump to System Settings behind the
        // Accessibility onboarding alert (or without an explicit user action).
        _ = LaunchAtLoginService.setEnabled(true, openSettingsIfNeeded: false)
    }

    @objc
    private func openHistory() {
        panelController.show()
    }

    @objc
    private func openSettings() {
        settingsWindowController.show()
    }

    @objc
    private func openAbout() {
        aboutWindowController.show()
    }

    @objc
    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear clipboard history?")
        alert.informativeText = String(localized: "This permanently removes all saved text, images, and file references.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Clear"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        historyStore.clear()
        panelController.hide()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
