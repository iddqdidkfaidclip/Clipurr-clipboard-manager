import AppKit
import ApplicationServices
import CoreGraphics

enum AccessibilityService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Separate TCC gate used by CGEvent.post. Advisory only — Accessibility
    /// alone is enough for AX text insert and System Events paste.
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    static var canAutomatePaste: Bool {
        isTrusted
    }

    /// Registers this binary in TCC so it appears under System Settings →
    /// Accessibility. Uses prompt:false so macOS does not show its own
    /// "Open System Settings" sheet (we open Settings only after the user
    /// explicitly chooses that in our UI).
    static func registerInAccessibilityList() {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestAccessPrompt() -> Bool {
        // String key avoids Swift 6 concurrency warning on kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightPostEventAccess() {
            CGRequestPostEventAccess()
        }
        return trusted
    }

    static func openSystemSettings() {
        // Register quietly first — opening Settings alone does not always add
        // an unsigned/adhoc (or freshly installed) app to the Accessibility list.
        // Do not call requestAccessPrompt() here: that shows a second system
        // dialog with "Open System Settings" while we already open the pane.
        registerInAccessibilityList()

        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
