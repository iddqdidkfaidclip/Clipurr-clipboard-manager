import AppKit
import SwiftUI

private final class HistoryPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // Defer so orderOut is not nested inside AppKit's resignKey cycle.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            self.onResignKey?()
        }
    }
}

@MainActor
final class HistoryPanelController {
    private let historyStore: HistoryStore
    private let pasteService: PasteService
    private let onOpenSettings: () -> Void
    private let panelState = HistoryPanelState()
    private let circularWindow = CircularHistoryWindow()
    private let panel: HistoryPanel
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(
        historyStore: HistoryStore,
        pasteService: PasteService,
        onOpenSettings: @escaping () -> Void
    ) {
        self.historyStore = historyStore
        self.pasteService = pasteService
        self.onOpenSettings = onOpenSettings
        let size = ClipurrTheme.historyPanelSize(for: AppSettings.panelSize)
        self.panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        let rootView = HistoryView(
            historyStore: historyStore,
            panelState: panelState,
            circularWindow: circularWindow,
            onSelect: { [weak self] entry in
                self?.select(entry)
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        let hosting = NSHostingController(rootView: rootView)
        // Prevent SwiftUI from resizing/recentering the panel to fit intrinsic content
        // (that made the window screen-wide so the UI looked stuck on the horizontal center).
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onResignKey = { [weak self] in
            self?.hide()
        }
    }

    func toggle(securePaste: Bool = false) {
        if panel.isVisible {
            if panelState.openedViaSecurePaste == securePaste {
                hide()
            } else {
                panelState.openedViaSecurePaste = securePaste
            }
        } else {
            show(securePaste: securePaste)
        }
    }

    func show(securePaste: Bool = false) {
        previousApp = NSWorkspace.shared.frontmostApplication
        historyStore.refresh()
        panelState.reset(
            entries: historyStore.entries,
            circularWindow: circularWindow,
            securePaste: securePaste
        )
        let frame = targetPanelFrame()
        applyPanelFrame(frame)
        panel.appearance = AppearanceStore.shared.theme.nsAppearance
        installKeyMonitor()
        installOutsideClickMonitor()
        panel.makeKeyAndOrderFront(nil)
        // AppKit can adjust the frame during orderFront — re-assert attachment.
        applyPanelFrame(frame)
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitor()
        removeOutsideClickMonitor()
    }

    private func openSettings() {
        hide()
        onOpenSettings()
    }

    private func select(_ entry: ClipboardEntry) {
        Task { @MainActor [weak self] in
            await self?.performSelect(entry)
        }
    }

    private func performSelect(_ entry: ClipboardEntry) async {
        let targetApp = previousApp

        // Stay open when Accessibility is missing — avoid hide→flash→error.
        if !AccessibilityService.isTrusted {
            switch await pasteService.paste(entry, into: nil) {
            case .failed:
                panelState.statusMessage = String(localized: "This item is no longer available.")
            default:
                bumpOnPasteIfNeeded(entry)
                panelState.statusMessage = String(localized: """
                Copied only. Enable Accessibility for Clipurr in System Settings \
                (Privacy & Security → Accessibility), then try again.
                """)
            }
            return
        }

        hide()
        switch await pasteService.paste(entry, into: targetApp) {
        case .pasted:
            bumpOnPasteIfNeeded(entry)
        case .copiedOnly:
            bumpOnPasteIfNeeded(entry)
            presentTransientStatus(String(localized: "Copied to clipboard."))
        case .failed:
            presentTransientStatus(String(localized: "This item is no longer available."))
        }
    }

    /// Persists a newer `createdAt` without reordering the visible list.
    private func bumpOnPasteIfNeeded(_ entry: ClipboardEntry) {
        guard AppSettings.moveToTopOnPaste else { return }
        historyStore.touchCreatedAt(entry)
    }

    private func presentTransientStatus(_ message: String) {
        // Re-open without overwriting the app we should paste back into.
        let savedTarget = previousApp
        let securePaste = panelState.openedViaSecurePaste
        historyStore.refresh()
        panelState.reset(
            entries: historyStore.entries,
            circularWindow: circularWindow,
            securePaste: securePaste
        )
        panelState.statusMessage = message
        let frame = targetPanelFrame()
        applyPanelFrame(frame)
        installKeyMonitor()
        installOutsideClickMonitor()
        panel.makeKeyAndOrderFront(nil)
        applyPanelFrame(frame)
        previousApp = savedTarget

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            self?.hide()
        }
    }

    private func performSelectedPaste() {
        guard let entry = panelState.selectedEntry(in: historyStore.entries) else { return }
        select(entry)
    }

    private func applyPanelFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        if let hosting = panel.contentViewController as? NSHostingController<HistoryView> {
            hosting.view.frame = NSRect(origin: .zero, size: frame.size)
        }
    }

    private func targetPanelFrame() -> NSRect {
        let size = ClipurrTheme.historyPanelSize(for: panelState.panelSize)
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main

        switch AppSettings.panelAnchor {
        case .center:
            guard let visibleFrame = mouseScreen?.visibleFrame else {
                return NSRect(origin: .zero, size: size)
            }
            let origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
            return NSRect(
                origin: Self.clampedOrigin(origin, panelSize: size, visibleFrame: visibleFrame),
                size: size
            )

        case .mouse:
            guard let visibleFrame = mouseScreen?.visibleFrame else {
                return NSRect(origin: .zero, size: size)
            }
            let mouseAnchor = CGRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1)
            let origin = Self.originBeside(
                anchor: mouseAnchor,
                panelSize: size,
                visibleFrame: visibleFrame
            )
            return NSRect(
                origin: Self.clampedOrigin(origin, panelSize: size, visibleFrame: visibleFrame),
                size: size
            )
        }
    }

    /// Places the panel beside `anchor` (right if it fits, else left), preferring the side with more room.
    private static func originBeside(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: NSRect,
        gap: CGFloat = 12
    ) -> NSPoint {
        let rightX = anchor.maxX + gap
        let leftX = anchor.minX - gap - panelSize.width
        let rightFits = rightX + panelSize.width <= visibleFrame.maxX
        let leftFits = leftX >= visibleFrame.minX

        let spaceRight = visibleFrame.maxX - anchor.maxX
        let spaceLeft = anchor.minX - visibleFrame.minX

        let x: CGFloat
        if rightFits, leftFits {
            x = spaceRight >= spaceLeft ? rightX : leftX
        } else if rightFits {
            x = rightX
        } else if leftFits {
            x = leftX
        } else {
            x = spaceRight >= spaceLeft
                ? visibleFrame.maxX - panelSize.width
                : visibleFrame.minX
        }

        var y = anchor.midY - panelSize.height / 2
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        return NSPoint(x: x, y: y)
    }

    private static func clampedOrigin(
        _ origin: NSPoint,
        panelSize: CGSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - panelSize.height))
        )
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            switch event.keyCode {
            case 125:
                self.panelState.moveSelection(by: 1, circularWindow: self.circularWindow)
                return nil
            case 126:
                self.panelState.moveSelection(by: -1, circularWindow: self.circularWindow)
                return nil
            case 36, 76:
                self.performSelectedPaste()
                return nil
            case 53:
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}
