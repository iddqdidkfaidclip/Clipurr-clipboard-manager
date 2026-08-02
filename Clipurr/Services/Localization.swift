import AppKit
import Foundation

enum Localization {
    private static let appleLanguagesKey = "AppleLanguages"

    /// Apply the user’s preferred language before building UI.
    /// Overrides take effect for `String(localized:)` / Bundle lookups in this process
    /// when set early; a full restart is still required after changing the preference.
    static func applyPreferredLanguage() {
        switch AppSettings.preferredLanguage {
        case .system:
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        default:
            guard let identifier = AppSettings.preferredLanguage.localeIdentifier else { return }
            UserDefaults.standard.set([identifier], forKey: appleLanguagesKey)
        }
    }

    /// Quit and reopen this app so language overrides take effect in a fresh process.
    @MainActor
    static func relaunchApplication() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$1\"", "--", appPath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
