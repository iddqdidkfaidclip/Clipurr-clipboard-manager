import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case belarusian = "be"
    case russian = "ru"
    case chineseSimplified = "zh-Hans"
    case spanish = "es"
    case arabic = "ar"
    case indonesian = "id"
    case portugueseBrazil = "pt-BR"
    case french = "fr"
    case japanese = "ja"
    case german = "de"
    case korean = "ko"
    case italian = "it"
    case turkish = "tr"
    case vietnamese = "vi"
    case polish = "pl"
    case dutch = "nl"
    case thai = "th"
    case chineseTraditional = "zh-Hant"
    case hindi = "hi"
    case persian = "fa"
    case swedish = "sv"
    case czech = "cs"
    case romanian = "ro"
    case hungarian = "hu"
    case greek = "el"
    case hebrew = "he"
    case danish = "da"
    case finnish = "fi"
    case norwegianBokmal = "nb"
    case malay = "ms"

    var id: String { rawValue }

    /// Autonym shown in the language picker (not localized).
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .belarusian: "Беларуская"
        case .russian: "Русский"
        case .chineseSimplified: "简体中文"
        case .spanish: "Español"
        case .arabic: "العربية"
        case .indonesian: "Bahasa Indonesia"
        case .portugueseBrazil: "Português (Brasil)"
        case .french: "Français"
        case .japanese: "日本語"
        case .german: "Deutsch"
        case .korean: "한국어"
        case .italian: "Italiano"
        case .turkish: "Türkçe"
        case .vietnamese: "Tiếng Việt"
        case .polish: "Polski"
        case .dutch: "Nederlands"
        case .thai: "ไทย"
        case .chineseTraditional: "繁體中文"
        case .hindi: "हिन्दी"
        case .persian: "فارسی"
        case .swedish: "Svenska"
        case .czech: "Čeština"
        case .romanian: "Română"
        case .hungarian: "Magyar"
        case .greek: "Ελληνικά"
        case .hebrew: "עברית"
        case .danish: "Dansk"
        case .finnish: "Suomi"
        case .norwegianBokmal: "Norsk Bokmål"
        case .malay: "Bahasa Melayu"
        }
    }

    var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }
}

enum HistoryContentMode: String, CaseIterable, Identifiable {
    case textOnly
    case textAndImages
    case textImagesAndFiles

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .textOnly: String(localized: "Text only")
        case .textAndImages: String(localized: "Text & images")
        case .textImagesAndFiles: String(localized: "Text, images & files")
        }
    }

    var storesImages: Bool {
        switch self {
        case .textOnly: false
        case .textAndImages, .textImagesAndFiles: true
        }
    }

    var storesFiles: Bool {
        self == .textImagesAndFiles
    }

    func stores(_ kind: ClipboardEntryKind) -> Bool {
        switch kind {
        case .text, .url:
            true
        case .image:
            storesImages
        case .files:
            storesFiles
        }
    }
}

enum HideCopiedContentMode: String, CaseIterable, Identifiable {
    case always
    case securePasteOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: String(localized: "Always")
        case .securePasteOnly: String(localized: "Secure Paste only")
        }
    }
}

enum HistoryClearInterval: String, CaseIterable, Identifiable {
    case never
    case onRestart
    case hourly
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: String(localized: "Never")
        case .onRestart: String(localized: "On restart")
        case .hourly: String(localized: "Every hour")
        case .daily: String(localized: "Every day")
        case .weekly: String(localized: "Every week")
        case .monthly: String(localized: "Every month")
        }
    }

    /// Calendar component used for timed auto-clear. `nil` means no timed interval.
    var calendarComponent: Calendar.Component? {
        switch self {
        case .never, .onRestart: nil
        case .hourly: .hour
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }
}

enum AppSettings {
    private static let historyLimitKey = "historyLimit"
    private static let didAskLaunchAtLoginKey = "didAskLaunchAtLogin"
    private static let preferredLanguageKey = "preferredLanguage"
    private static let historyContentModeKey = "historyContentMode"
    private static let hideCopiedContentModeKey = "hideCopiedContentMode"
    private static let historyClearIntervalKey = "historyClearInterval"
    private static let lastAutomaticHistoryClearKey = "lastAutomaticHistoryClear"
    private static let encryptHistoryKey = "encryptHistory"
    /// Legacy bool from the old blur toggle — migrated into `hideCopiedContentMode`.
    private static let blurUnfocusedImagesKey = "blurUnfocusedImages"
    static let defaultHistoryLimit = 10
    static let maxHistoryLimit = 1000
    static let defaultEncryptHistory = true

    static var historyLimit: Int {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: historyLimitKey)
            guard storedValue > 0 else { return defaultHistoryLimit }
            return min(storedValue, maxHistoryLimit)
        }
        set {
            let clamped = min(max(1, newValue), maxHistoryLimit)
            UserDefaults.standard.set(clamped, forKey: historyLimitKey)
        }
    }

    static var didAskLaunchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: didAskLaunchAtLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: didAskLaunchAtLoginKey) }
    }

    static var preferredLanguage: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: preferredLanguageKey) ?? ""
            if let language = AppLanguage(rawValue: raw) {
                return language
            }
            // Migrate legacy raw values from the pre-localization stub.
            let migrated: AppLanguage
            switch raw {
            case "english": migrated = .english
            default: migrated = .system
            }
            UserDefaults.standard.set(migrated.rawValue, forKey: preferredLanguageKey)
            return migrated
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferredLanguageKey)
        }
    }

    static var historyContentMode: HistoryContentMode {
        get {
            let raw = UserDefaults.standard.string(forKey: historyContentModeKey) ?? ""
            return HistoryContentMode(rawValue: raw) ?? .textAndImages
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: historyContentModeKey)
        }
    }

    static var storesImages: Bool {
        historyContentMode.storesImages
    }

    static var hideCopiedContentMode: HideCopiedContentMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: hideCopiedContentModeKey),
               let mode = HideCopiedContentMode(rawValue: raw) {
                return mode
            }
            // Migrate legacy blur toggle: on → always, off → secure paste only.
            let migrated: HideCopiedContentMode = UserDefaults.standard.bool(
                forKey: blurUnfocusedImagesKey
            ) ? .always : .securePasteOnly
            UserDefaults.standard.set(migrated.rawValue, forKey: hideCopiedContentModeKey)
            return migrated
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: hideCopiedContentModeKey)
        }
    }

    static var historyClearInterval: HistoryClearInterval {
        get {
            let raw = UserDefaults.standard.string(forKey: historyClearIntervalKey) ?? ""
            return HistoryClearInterval(rawValue: raw) ?? .never
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: historyClearIntervalKey)
            // Restart the timed window so enabling a schedule does not clear immediately.
            if newValue.calendarComponent != nil {
                lastAutomaticHistoryClear = .now
            }
        }
    }

    static var lastAutomaticHistoryClear: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: lastAutomaticHistoryClearKey)
            guard interval > 0 else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastAutomaticHistoryClearKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastAutomaticHistoryClearKey)
            }
        }
    }

    /// When on, sensitive history fields are sealed with a local AES key (default on).
    static var encryptHistory: Bool {
        get {
            guard UserDefaults.standard.object(forKey: encryptHistoryKey) != nil else {
                return defaultEncryptHistory
            }
            return UserDefaults.standard.bool(forKey: encryptHistoryKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: encryptHistoryKey)
        }
    }
}
