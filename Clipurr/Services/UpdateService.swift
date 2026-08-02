import AppKit
import Sparkle

/// Owns the Sparkle updater for menu-bar “Check for Updates…”.
@MainActor
final class UpdateService: NSObject {
    static let shared = UpdateService()

    private let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var updaterController: SPUStandardUpdaterController { controller }

    @objc
    func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
