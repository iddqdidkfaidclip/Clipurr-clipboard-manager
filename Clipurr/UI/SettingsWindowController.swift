import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let historyStore: HistoryStore
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
    }

    func show() {
        if window == nil {
            let hostingController = NSHostingController(rootView: makeSettingsView())
            hostingController.sizingOptions = [.intrinsicContentSize]
            self.hostingController = hostingController

            let settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow.title = String(localized: "Clipurr Settings")
            settingsWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.titleVisibility = .hidden
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.isMovableByWindowBackground = true
            fitContent(in: settingsWindow, hostingController: hostingController)
            settingsWindow.center()
            AppearanceStore.shared.applyToOpenWindows()
            window = settingsWindow
        } else if let window, let hostingController {
            // Language/content length can change intrinsic height — re-fit.
            fitContent(in: window, hostingController: hostingController)
            AppearanceStore.shared.applyToOpenWindows()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(historyStore: historyStore) { [weak self] in
            self?.refitContent()
        }
    }

    private func refitContent() {
        guard let window, let hostingController else { return }
        fitContent(in: window, hostingController: hostingController)
    }

    private func fitContent(
        in window: NSWindow,
        hostingController: NSHostingController<SettingsView>
    ) {
        hostingController.view.layoutSubtreeIfNeeded()
        let width = ClipurrTheme.settingsWidth
        let fitting = hostingController.sizeThatFits(in: NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        window.setContentSize(NSSize(
            width: max(width, fitting.width),
            height: max(1, fitting.height)
        ))
    }
}
