import Foundation

enum AppVersion {
    /// Marketing version, e.g. `1.0.1`.
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }

    /// Build number (`CFBundleVersion`), used by Sparkle for comparisons.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
    }
}
