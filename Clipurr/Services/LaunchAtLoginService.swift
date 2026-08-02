import AppKit
import ServiceManagement

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool, openSettingsIfNeeded: Bool = true) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            if openSettingsIfNeeded, SMAppService.mainApp.status == .requiresApproval {
                openLoginItemsSettings()
            }
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
