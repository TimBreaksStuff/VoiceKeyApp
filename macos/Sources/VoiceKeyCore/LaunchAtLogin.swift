import Foundation

/// What the system reports about opening VoiceKey when the user logs in.
public enum LaunchAtLoginState: Equatable {
    case on
    case off
    /// Registered, but switched off in the system's own login items list.
    case blocked
}

/// What a click on the sidebar's launch-at-login row asks for.
public enum LaunchAtLoginAction: Equatable { case enable, disable, openSettings }

/// The sidebar row that opens VoiceKey at login. Pure — the platform reads the
/// state from the system and carries the action out; this decides what the row
/// says and what clicking it means.
public enum LaunchAtLogin {

    /// - Parameter title: The platform's own wording — "Open at login".
    public static func label(_ title: String, _ state: LaunchAtLoginState) -> String {
        "\(title) — \(word(state))"
    }

    /// Blocked asks for the system's list rather than a registration it already
    /// has: registering again would change nothing and read as a dead row.
    public static func click(_ state: LaunchAtLoginState) -> LaunchAtLoginAction {
        switch state {
        case .on: return .disable
        case .off: return .enable
        case .blocked: return .openSettings
        }
    }

    private static func word(_ state: LaunchAtLoginState) -> String {
        switch state {
        case .on: return "On"
        case .off: return "Off"
        case .blocked: return "Blocked"
        }
    }
}
