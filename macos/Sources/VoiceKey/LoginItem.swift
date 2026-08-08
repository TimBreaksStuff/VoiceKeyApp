import ServiceManagement
import VoiceKeyCore

/// Opening VoiceKey at login. `SMAppService.mainApp` registers the bundle
/// itself, so there is no helper to ship and nothing to install — the app has
/// to be somewhere Launch Services can find it again, which is the same
/// requirement the TCC grants already have.
enum LoginItem {

    static var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        // Registered, then switched off in System Settings › General › Login Items.
        case .requiresApproval: return .blocked
        default: return .off
        }
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.line("launch at login \(enabled ? "registered" : "unregistered")")
        } catch {
            Log.line("launch at login \(enabled ? "register" : "unregister") FAILED: \(error)")
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
