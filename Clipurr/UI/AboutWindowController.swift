import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AboutView>?

    func show() {
        if window == nil {
            let hostingController = NSHostingController(rootView: AboutView())
            hostingController.sizingOptions = [.intrinsicContentSize]
            self.hostingController = hostingController

            let aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow.title = String(localized: "About Clipurr")
            aboutWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            aboutWindow.titlebarAppearsTransparent = true
            aboutWindow.titleVisibility = .hidden
            aboutWindow.isReleasedWhenClosed = false
            aboutWindow.isMovableByWindowBackground = true
            fitContent(in: aboutWindow, hostingController: hostingController)
            aboutWindow.center()
            AppearanceStore.shared.applyToOpenWindows()
            window = aboutWindow
        } else if let window, let hostingController {
            fitContent(in: window, hostingController: hostingController)
            AppearanceStore.shared.applyToOpenWindows()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func fitContent(
        in window: NSWindow,
        hostingController: NSHostingController<AboutView>
    ) {
        hostingController.view.layoutSubtreeIfNeeded()
        let width: CGFloat = 340
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
