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

enum PanelSize: String, CaseIterable, Identifiable {
    case extraSmall
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .extraSmall: String(localized: "Extra Small")
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

enum PanelAnchor: String, CaseIterable, Identifiable {
    case center
    case mouse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .center: String(localized: "Center")
        case .mouse: String(localized: "Mouse cursor")
        }
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

/// Accent used for selection rings, panel borders, and highlights.
enum AccentColorChoice: String, CaseIterable, Identifiable {
    case blue
    case pink
    case purple
    case green
    case orange
    case teal
    case red
    case yellow
    case custom

    var id: String { rawValue }

    /// Built-in swatches (excludes the custom color-wheel entry).
    static var presets: [AccentColorChoice] {
        allCases.filter { $0 != .custom }
    }

    var displayName: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .teal: String(localized: "Teal")
        case .red: String(localized: "Red")
        case .yellow: String(localized: "Yellow")
        case .custom: String(localized: "Custom")
        }
    }
}

/// Window chrome themes (dark / soft dark / light).
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case black
    case softBlack
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: String(localized: "Black")
        case .softBlack: String(localized: "Soft Black")
        case .light: String(localized: "Light")
        }
    }
}

/// Backdrop treatment for the history panel only.
enum HistoryBackgroundEffect: String, CaseIterable, Identifiable {
    case blur
    case glass
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blur: String(localized: "Blur")
        case .glass: String(localized: "Glass")
        case .none: String(localized: "None")
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
    private static let moveToTopOnPasteKey = "moveToTopOnPaste"
    private static let panelSizeKey = "panelSize"
    private static let panelAnchorKey = "panelAnchor"
    private static let accentColorKey = "accentColor"
    private static let customAccentHexKey = "customAccentHex"
    private static let appearanceThemeKey = "appearanceTheme"
    private static let backgroundOpacityKey = "backgroundOpacity"
    private static let backgroundEffectKey = "backgroundEffect"
    /// Legacy bool from the old blur toggle — migrated into `hideCopiedContentMode`.
    private static let blurUnfocusedImagesKey = "blurUnfocusedImages"
    static let defaultHistoryLimit = 30
    static let maxHistoryLimit = 1000
    static let defaultEncryptHistory = true
    static let defaultMoveToTopOnPaste = false
    static let defaultPanelSize: PanelSize = .large
    static let defaultPanelAnchor: PanelAnchor = .center
    static let defaultAccentColor: AccentColorChoice = .blue
    /// Soft blue matching the built-in blue swatch (`#58A6FF`) for the color-wheel seed.
    static let defaultCustomAccentHex: UInt32 = 0x58A6FF
    static let defaultAppearanceTheme: AppearanceTheme = .softBlack
    static let defaultBackgroundEffect: HistoryBackgroundEffect = .glass
    /// History panel tint opacity percent (1…100).
    static let defaultBackgroundOpacity = 75
    static let minBackgroundOpacity = 1
    static let maxBackgroundOpacity = 100

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

    /// When on, pasting from history updates that item’s `createdAt` so it ranks first next open (default off).
    static var moveToTopOnPaste: Bool {
        get {
            guard UserDefaults.standard.object(forKey: moveToTopOnPasteKey) != nil else {
                return defaultMoveToTopOnPaste
            }
            return UserDefaults.standard.bool(forKey: moveToTopOnPasteKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: moveToTopOnPasteKey)
        }
    }

    static var panelSize: PanelSize {
        get {
            let raw = UserDefaults.standard.string(forKey: panelSizeKey) ?? ""
            return PanelSize(rawValue: raw) ?? defaultPanelSize
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: panelSizeKey)
        }
    }

    static var panelAnchor: PanelAnchor {
        get {
            let raw = UserDefaults.standard.string(forKey: panelAnchorKey) ?? ""
            // Migrate removed "inputField" / text-cursor option → center.
            if raw == "inputField" {
                UserDefaults.standard.set(PanelAnchor.center.rawValue, forKey: panelAnchorKey)
                return .center
            }
            return PanelAnchor(rawValue: raw) ?? defaultPanelAnchor
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: panelAnchorKey)
        }
    }

    static var accentColor: AccentColorChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: accentColorKey) ?? ""
            return AccentColorChoice(rawValue: raw) ?? defaultAccentColor
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: accentColorKey)
        }
    }

    /// sRGB hex (`0xRRGGBB`) for `AccentColorChoice.custom`.
    static var customAccentHex: UInt32 {
        get {
            guard UserDefaults.standard.object(forKey: customAccentHexKey) != nil else {
                return defaultCustomAccentHex
            }
            return UInt32(UserDefaults.standard.integer(forKey: customAccentHexKey))
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: customAccentHexKey)
        }
    }

    static var appearanceTheme: AppearanceTheme {
        get {
            let raw = UserDefaults.standard.string(forKey: appearanceThemeKey) ?? ""
            return AppearanceTheme(rawValue: raw) ?? defaultAppearanceTheme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceThemeKey)
        }
    }

    /// History panel tint opacity as a percent (1…100). Default 75.
    static var backgroundOpacity: Int {
        get {
            guard UserDefaults.standard.object(forKey: backgroundOpacityKey) != nil else {
                return defaultBackgroundOpacity
            }
            let stored = UserDefaults.standard.integer(forKey: backgroundOpacityKey)
            return min(max(stored, minBackgroundOpacity), maxBackgroundOpacity)
        }
        set {
            let clamped = min(max(newValue, minBackgroundOpacity), maxBackgroundOpacity)
            UserDefaults.standard.set(clamped, forKey: backgroundOpacityKey)
        }
    }

    static var backgroundEffect: HistoryBackgroundEffect {
        get {
            let raw = UserDefaults.standard.string(forKey: backgroundEffectKey) ?? ""
            return HistoryBackgroundEffect(rawValue: raw) ?? defaultBackgroundEffect
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: backgroundEffectKey)
        }
    }
}
