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
    private let panelState = HistoryPanelState()
    private let panel: HistoryPanel
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(historyStore: HistoryStore, pasteService: PasteService) {
        self.historyStore = historyStore
        self.pasteService = pasteService
        let size = ClipurrTheme.historyPanelSize
        self.panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        let rootView = HistoryView(
            historyStore: historyStore,
            panelState: panelState,
            onSelect: { [weak self] entry in
                self?.select(entry)
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
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
        panelState.reset(entries: historyStore.entries, securePaste: securePaste)
        positionPanel()
        installKeyMonitor()
        installOutsideClickMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitor()
        removeOutsideClickMonitor()
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
            break
        case .copiedOnly:
            presentTransientStatus(String(localized: "Copied to clipboard."))
        case .failed:
            presentTransientStatus(String(localized: "This item is no longer available."))
        }
    }

    private func presentTransientStatus(_ message: String) {
        // Re-open without overwriting the app we should paste back into.
        let savedTarget = previousApp
        let securePaste = panelState.openedViaSecurePaste
        historyStore.refresh()
        panelState.reset(entries: historyStore.entries, securePaste: securePaste)
        panelState.statusMessage = message
        positionPanel()
        installKeyMonitor()
        installOutsideClickMonitor()
        panel.makeKeyAndOrderFront(nil)
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

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            switch event.keyCode {
            case 125:
                self.panelState.moveSelection(by: 1, entries: self.historyStore.entries)
                return nil
            case 126:
                self.panelState.moveSelection(by: -1, entries: self.historyStore.entries)
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
