import AppKit
import SwiftUI

/// Live appearance preferences shared by history, settings, and about windows.
@Observable
@MainActor
final class AppearanceStore {
    static let shared = AppearanceStore()

    var accent: AccentColorChoice
    var customAccent: Color
    var theme: AppearanceTheme
    /// History panel backdrop effect.
    var backgroundEffect: HistoryBackgroundEffect
    /// History panel tint opacity percent (1…100).
    var backgroundOpacity: Int

    private init() {
        accent = AppSettings.accentColor
        customAccent = Color(hex: AppSettings.customAccentHex)
        theme = AppSettings.appearanceTheme
        backgroundEffect = AppSettings.backgroundEffect
        backgroundOpacity = AppSettings.backgroundOpacity
    }

    var accentColor: Color {
        accent == .custom ? customAccent : accent.swiftUIColor
    }

    var palette: ThemePalette { theme.palette }

    var colorScheme: ColorScheme { theme.colorScheme }

    /// 0…1 multiplier for the history panel tint.
    var historyTintAlpha: Double {
        Double(backgroundOpacity) / 100
    }

    func setAccent(_ value: AccentColorChoice) {
        guard accent != value else { return }
        accent = value
        AppSettings.accentColor = value
    }

    func setCustomAccent(_ color: Color) {
        let hex = color.sRGBHex
        customAccent = Color(hex: hex)
        accent = .custom
        AppSettings.accentColor = .custom
        AppSettings.customAccentHex = hex
    }

    func setTheme(_ value: AppearanceTheme) {
        guard theme != value else { return }
        theme = value
        AppSettings.appearanceTheme = value
        applyToOpenWindows()
    }

    func setBackgroundEffect(_ value: HistoryBackgroundEffect) {
        guard backgroundEffect != value else { return }
        backgroundEffect = value
        AppSettings.backgroundEffect = value
    }

    func setBackgroundOpacity(_ value: Int) {
        let clamped = min(
            max(value, AppSettings.minBackgroundOpacity),
            AppSettings.maxBackgroundOpacity
        )
        guard backgroundOpacity != clamped else { return }
        backgroundOpacity = clamped
        AppSettings.backgroundOpacity = clamped
    }

    func applyToOpenWindows() {
        let appearance = theme.nsAppearance
        // Settings / About stay fully opaque — opacity & effects are history-only.
        let canvas = NSColor(palette.canvas)
        for window in NSApp.windows {
            // Status-item / system chrome must keep system appearance so template
            // menu-bar icons track the menu bar, not the in-app theme.
            if Self.followsSystemAppearance(window) {
                window.appearance = nil
                continue
            }
            window.appearance = appearance
            if window.styleMask.contains(.titled) {
                window.isOpaque = true
                window.backgroundColor = canvas
            }
        }
    }

    /// Settings/About (titled) and the floating history panel are themed; menu bar is not.
    private static func followsSystemAppearance(_ window: NSWindow) -> Bool {
        if window.styleMask.contains(.titled) { return false }
        if window.level == .floating { return false }
        return true
    }
}

struct ThemePalette {
    /// Main window / panel fill (GitHub `bgColor-default`).
    let canvas: Color
    /// Raised cards / sections (GitHub `bgColor-muted`).
    let elevated: Color
    /// Inputs and inset controls.
    let control: Color
    /// Hairline borders (GitHub `borderColor-default`).
    let border: Color
}

enum ClipurrTheme {
    static let settingsWidth: CGFloat = 500

    static func historyPanelSize(for size: PanelSize) -> CGSize {
        switch size {
        case .extraSmall: CGSize(width: 320, height: 260)
        case .small: CGSize(width: 400, height: 320)
        case .medium: CGSize(width: 460, height: 380)
        case .large: CGSize(width: 728, height: 588)
        }
    }

    /// Default / legacy large panel size.
    static let historyPanelSize = historyPanelSize(for: .large)

    /// Accent used for selection rings and panel borders.
    @MainActor
    static var selectionHighlight: Color { AppearanceStore.shared.accentColor }

    static let trafficLightClose = Color(red: 1, green: 0.38, blue: 0.35)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.38)
    static let danger = Color(red: 0.90, green: 0.28, blue: 0.28)

    enum Radius {
        static let control: CGFloat = 6
        static let preview: CGFloat = 7
        static let icon: CGFloat = 8
        static let row: CGFloat = 10
        static let section: CGFloat = 12
    }

    enum Spacing {
        static let rowList: CGFloat = 6
        static let sectionInner: CGFloat = 8
        static let settingsSections: CGFloat = 22
        static let headerIcon: CGFloat = 10
        static let rowContent: CGFloat = 12
        static let statusHorizontal: CGFloat = 14
        static let headerHorizontal: CGFloat = 16
        static let settingsOuter: CGFloat = 20
    }

    static let rowTitleFont = Font.system(size: 13, weight: .medium)
    static let previewSize: CGFloat = 42
    static let contentBlurRadius: CGFloat = 6
    static let historyHeaderHeight: CGFloat = 48
}

extension AccentColorChoice {
    /// Soft accents tuned to read on both light and dark Primer canvases.
    var swiftUIColor: Color {
        switch self {
        case .blue: Color(hex: 0x58A6FF)
        case .pink: Color(red: 1.0, green: 0.72, blue: 0.80)
        case .purple: Color(hex: 0xBC8CFF)
        case .green: Color(hex: 0x3FB950)
        case .orange: Color(hex: 0xF0883E)
        case .teal: Color(hex: 0x39C5CF)
        case .red: Color(hex: 0xFF7B72)
        case .yellow: Color(hex: 0xE3B341)
        case .custom: Color(hex: AppSettings.customAccentHex)
        }
    }
}

extension AppearanceTheme {
    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    var nsAppearance: NSAppearance? {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }

    /// GitHub Primer-inspired surfaces (dark / dark_dimmed / light).
    var palette: ThemePalette {
        switch self {
        case .black:
            ThemePalette(
                canvas: Color(hex: 0x0D1117),
                elevated: Color(hex: 0x161B22),
                control: Color(hex: 0x21262D),
                border: Color(hex: 0x30363D)
            )
        case .softBlack:
            ThemePalette(
                canvas: Color(hex: 0x22272E),
                elevated: Color(hex: 0x2D333B),
                control: Color(hex: 0x373E47),
                border: Color(hex: 0x444C56)
            )
        case .light:
            ThemePalette(
                canvas: Color(hex: 0xFFFFFF),
                elevated: Color(hex: 0xF6F8FA),
                control: Color(hex: 0xFFFFFF),
                border: Color(hex: 0xD0D7DE)
            )
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Packed sRGB `0xRRGGBB` for persistence.
    var sRGBHex: UInt32 {
        let nsColor = NSColor(self)
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = UInt32((min(max(red, 0), 1) * 255).rounded())
        let g = UInt32((min(max(green, 0), 1) * 255).rounded())
        let b = UInt32((min(max(blue, 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    var isAccentCheckmarkDark: Bool {
        let nsColor = NSColor(self)
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // Relative luminance — light accents need a dark checkmark.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62
    }
}

extension View {
    /// Applies the shared accent + canvas color scheme.
    @MainActor
    func clipurrAppearance(_ appearance: AppearanceStore) -> some View {
        preferredColorScheme(appearance.colorScheme)
            .tint(appearance.accentColor)
    }
}

/// History panel backdrop: solid tint, blur, or glass over the desktop.
struct HistoryPanelBackground: View {
    let effect: HistoryBackgroundEffect
    let canvas: Color
    let tintAlpha: Double
    let border: Color
    let shape: RoundedRectangle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch effect {
            case .none:
                shape.fill(canvas.opacity(tintAlpha))
            case .blur:
                BehindWindowBlur(material: .sidebar, cornerRadius: ClipurrTheme.Radius.row)
                shape.fill(canvas.opacity(tintAlpha))
            case .glass:
                BehindWindowBlur(material: .hudWindow, cornerRadius: ClipurrTheme.Radius.row)
                shape.fill(canvas.opacity(tintAlpha * 0.72))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            panelBorder
        }
    }

    @ViewBuilder
    private var panelBorder: some View {
        switch effect {
        case .none:
            shape.strokeBorder(border.opacity(0.95), lineWidth: 1)
        case .blur:
            shape.strokeBorder(.regularMaterial, lineWidth: 1.5)
            shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        case .glass:
            shape.strokeBorder(.ultraThinMaterial, lineWidth: 1.75)
            shape.strokeBorder(
                Color.white.opacity(colorScheme == .dark ? 0.28 : 0.55),
                lineWidth: 1
            )
        }
    }
}

/// Blurs content behind a transparent panel (`NSVisualEffectView`).
private struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.layer?.cornerRadius = cornerRadius
    }
}
