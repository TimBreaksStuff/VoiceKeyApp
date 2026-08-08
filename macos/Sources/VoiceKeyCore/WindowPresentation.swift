import Foundation

/// State of one thing the app needs before it can dictate.
public enum Grant: Equatable {
    case granted
    case denied
    /// Never asked, or still in flight.
    case pending
    /// Asked and refused elsewhere, or simply not established.
    case unknown
}

/// Everything the main window's header shows about the engine. Pure — the view
/// only draws what this returns.
public struct WindowPresentation: Equatable {

    public enum Subject: Equatable { case microphone, accessibility, model }

    /// Which palette the engine pill wears — the colour carries the state on its own.
    public enum Tone: Equatable { case ready, listening, working, blocked }

    public struct Pill: Equatable {
        public let label: String
        public let tone: Tone
        /// True when clicking the pill should lead somewhere — an error.
        public let isActionable: Bool
    }

    public struct PermissionLine: Equatable {
        public let subject: Subject
        /// "microphone · granted"
        public let text: String
        /// True when the line is worth clicking: something is missing.
        public let needsAttention: Bool
    }

    /// "Wednesday, 5 August" — the view uppercases it.
    public let dateLine: String
    public let pill: Pill
    public let permissions: [PermissionLine]

    /// How many dictations it takes before the strip has served its purpose.
    private static let onboardingDictations = 3

    public static func make(status: DictationStatus,
                            now: Date = Date(), calendar: Calendar = .current,
                            microphone: Grant, accessibility: Grant,
                            model: Grant) -> WindowPresentation {
        WindowPresentation(
            dateLine: dateLine(now, calendar: calendar),
            pill: pill(for: status),
            permissions: [
                line(.microphone, microphone, granted: "granted", missing: "denied"),
                line(.accessibility, accessibility, granted: "granted", missing: "not granted"),
                line(.model, model, granted: "loaded", missing: "unavailable"),
            ])
    }

    /// Whether the getting-started strip belongs on screen. It retires itself once
    /// the shortcut is plainly in the user's hands, and a dismissal is permanent.
    public static func showsOnboarding(dismissed: Bool, transcripts: Int) -> Bool {
        !dismissed && transcripts < onboardingDictations
    }

    private static func dateLine(_ now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: now)
    }

    private static func pill(for status: DictationStatus) -> Pill {
        switch status {
        case .loading: return Pill(label: "Preparing…", tone: .working, isActionable: false)
        case .idle: return Pill(label: "Ready", tone: .ready, isActionable: false)
        case .recording: return Pill(label: "Listening…", tone: .listening, isActionable: false)
        case .transcribing: return Pill(label: "Transcribing…", tone: .working, isActionable: false)
        case .error(let message): return Pill(label: message, tone: .blocked, isActionable: true)
        }
    }

    private static func line(_ subject: Subject, _ grant: Grant,
                             granted: String, missing: String) -> PermissionLine {
        let value: String
        switch grant {
        case .granted: value = granted
        case .denied: value = missing
        case .pending: value = subject == .model ? "loading" : "not asked"
        case .unknown: value = missing
        }
        return PermissionLine(subject: subject, text: "\(name(subject)) · \(value)",
                              needsAttention: grant != .granted)
    }

    private static func name(_ subject: Subject) -> String {
        switch subject {
        case .microphone: return "microphone"
        case .accessibility: return "accessibility"
        case .model: return "model"
        }
    }
}
