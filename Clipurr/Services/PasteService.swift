import AppKit
import CoreGraphics
import Foundation

enum PasteOutcome {
    case pasted
    case copiedOnly
    case failed
}

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?

    init(
        pasteboard: NSPasteboard = .general,
        monitor: ClipboardMonitor
    ) {
        self.pasteboard = pasteboard
        self.monitor = monitor
    }

    func paste(
        _ entry: ClipboardEntry,
        into targetApp: NSRunningApplication?
    ) async -> PasteOutcome {
        guard writeToPasteboard(entry) else {
            return .failed
        }
        monitor?.markCurrentChangeAsHandled()

        guard AccessibilityService.isTrusted else {
            return .copiedOnly
        }

        await restoreFocus(to: targetApp)

        // Prefer real Cmd+V. AX SelectedText often only selects-all in Electron
        // (Cursor) without inserting, and System Events pops an Automation prompt.
        clearStickyModifiers()
        postCommandV()
        return .pasted
    }

    private func writeToPasteboard(_ entry: ClipboardEntry) -> Bool {
        pasteboard.clearContents()
        let payload = entry.plaintextPayload()

        switch entry.kind {
        case .text:
            guard let text = String(data: payload, encoding: .utf8) else {
                return false
            }
            return pasteboard.setString(text, forType: .string)

        case .url:
            guard let text = String(data: payload, encoding: .utf8) else {
                return false
            }
            let wroteString = pasteboard.setString(text, forType: .string)
            let wroteURL = pasteboard.setString(text, forType: .URL)
            return wroteString || wroteURL

        case .image:
            return pasteboard.setData(
                payload,
                forType: NSPasteboard.PasteboardType(entry.pasteboardType)
            )

        case .files:
            guard let paths = try? ClipboardPayloadCodec.decodeFilePaths(payload) else {
                return false
            }
            let urls = paths
                .map { NSURL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path ?? "") }
            guard !urls.isEmpty else { return false }
            return pasteboard.writeObjects(urls)
        }
    }

    private func restoreFocus(to targetApp: NSRunningApplication?) async {
        try? await Task.sleep(for: .milliseconds(50))

        if let targetApp, !targetApp.isTerminated {
            targetApp.activate(options: [.activateIgnoringOtherApps])

            let deadline = ContinuousClock.now + .milliseconds(400)
            while ContinuousClock.now < deadline {
                if targetApp.isActive { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        try? await Task.sleep(for: .milliseconds(30))
    }

    /// Release modifiers that may still be down from ⇧⌘V / ⇧⌃⌘V so the
    /// synthesized ⌘V is not interpreted as ⌘⇧V / select-all chords.
    private func clearStickyModifiers() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let modifierKeys: [CGKeyCode] = [
            56, // left shift
            60, // right shift
            59, // left control
            62, // right control
            58, // left option
            61, // right option
            55, // left command
            54  // right command
        ]
        for key in modifierKeys {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            event?.post(tap: .cgSessionEventTap)
        }
    }

    private func postCommandV() {
        let vKey: CGKeyCode = 9 // kVK_ANSI_V — physical key, layout-independent
        // 0x000008 marks a real left/right modifier press — needed by some apps
        // (see Flycut/Maccy). Without it, synthesized Cmd+V is often ignored.
        let cmdFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKey,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKey,
                keyDown: false
              ) else {
            return
        }

        keyDown.flags = cmdFlags
        keyUp.flags = cmdFlags

        let timestamp = mach_absolute_time()
        keyDown.timestamp = timestamp
        keyUp.timestamp = timestamp

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
