import SwiftUI

@main
struct ClipurrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings content is shown via SettingsWindowController from the menu bar.
        Settings {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
}
