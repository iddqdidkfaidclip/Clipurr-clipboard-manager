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
            // Create an empty themed window first so AppKit controls inherit the
            // in-app appearance on the first layout (avoids white-on-white pickers).
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: ClipurrTheme.settingsWidth, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = String(localized: "Clipurr Settings")
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.titleVisibility = .hidden
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.isMovableByWindowBackground = true
            AppearanceStore.shared.apply(to: settingsWindow)

            let hostingController = NSHostingController(rootView: makeSettingsView())
            // Manual fit keeps tab switches from fighting Auto Layout intrinsic
            // resizing (that duel is what made the chrome flash).
            hostingController.sizingOptions = []
            hostingController.view.appearance = AppearanceStore.shared.theme.nsAppearance
            self.hostingController = hostingController

            settingsWindow.contentViewController = hostingController
            fitContent(in: settingsWindow, hostingController: hostingController, animated: false)
            settingsWindow.center()
            window = settingsWindow
        } else if let window, let hostingController {
            AppearanceStore.shared.apply(to: window)
            hostingController.view.appearance = AppearanceStore.shared.theme.nsAppearance
            // Language/content length can change intrinsic height — re-fit.
            fitContent(in: window, hostingController: hostingController, animated: false)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(historyStore: historyStore) { [weak self] animated in
            self?.refitContent(animated: animated)
        }
    }

    private func refitContent(animated: Bool) {
        guard let window, let hostingController else { return }
        fitContent(in: window, hostingController: hostingController, animated: animated)
    }

    private func fitContent(
        in window: NSWindow,
        hostingController: NSHostingController<SettingsView>,
        animated: Bool
    ) {
        hostingController.view.layoutSubtreeIfNeeded()
        let width = ClipurrTheme.settingsWidth
        let fitting = hostingController.sizeThatFits(in: NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        let contentSize = NSSize(
            width: max(width, fitting.width),
            height: max(1, fitting.height)
        )

        let targetFrame = framePreservingTopEdge(for: window, contentSize: contentSize)
        let current = window.frame
        guard abs(current.width - targetFrame.width) > 0.5
            || abs(current.height - targetFrame.height) > 0.5
        else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    /// Grow/shrink from the bottom so the titlebar doesn’t jump on tab changes.
    private func framePreservingTopEdge(for window: NSWindow, contentSize: NSSize) -> NSRect {
        let frameForContent = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var frame = window.frame
        let heightDelta = frameForContent.height - frame.height
        frame.size = frameForContent.size
        frame.origin.y -= heightDelta
        return frame
    }
}
