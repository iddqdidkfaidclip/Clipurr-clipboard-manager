import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<AboutView>?

    func show() {
        if window == nil {
            let aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            aboutWindow.title = String(localized: "About Clipurr")
            aboutWindow.titlebarAppearsTransparent = true
            aboutWindow.titleVisibility = .hidden
            aboutWindow.isReleasedWhenClosed = false
            aboutWindow.isMovableByWindowBackground = true
            AppearanceStore.shared.apply(to: aboutWindow)

            let hostingController = NSHostingController(rootView: AboutView())
            hostingController.sizingOptions = [.intrinsicContentSize]
            hostingController.view.appearance = AppearanceStore.shared.theme.nsAppearance
            self.hostingController = hostingController

            aboutWindow.contentViewController = hostingController
            fitContent(in: aboutWindow, hostingController: hostingController)
            aboutWindow.center()
            window = aboutWindow
        } else if let window, let hostingController {
            AppearanceStore.shared.apply(to: window)
            hostingController.view.appearance = AppearanceStore.shared.theme.nsAppearance
            fitContent(in: window, hostingController: hostingController)
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
