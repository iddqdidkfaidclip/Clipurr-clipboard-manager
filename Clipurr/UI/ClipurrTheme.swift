import SwiftUI

enum ClipurrTheme {
    static let historyPanelSize = CGSize(width: 520, height: 420)
    static let settingsWidth: CGFloat = 500

    static let selectionHighlight = Color(red: 1.0, green: 0.72, blue: 0.80)
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
