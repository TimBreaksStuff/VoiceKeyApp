import Foundation

/// What the app is doing right now. Drives the menu-bar glyph and the menu header.
public enum DictationStatus: Equatable {
    case loading
    case idle
    case recording(elapsed: Int)
    case transcribing
    case error(String)

    /// Where to land when nothing is happening. Idle — unless the shortcut never
    /// bound, in which case that is the one thing the user needs to know, and
    /// anything finishing afterwards must not paper over it with "Ready".
    public static func settled(shortcutIsBound: Bool, shortcut: String) -> DictationStatus {
        shortcutIsBound ? .idle : .error("\(shortcut) is taken by another app")
    }
}

/// Everything the menu bar needs to render a state: a one-or-two-word title, a
/// dim right-hand meta value, the label of the primary action, and which glyph
/// to show. Pure — the AppKit side only draws what this returns.
public struct StatusPresentation: Equatable {
    public enum Glyph: Equatable { case idle, recording }

    public let title: String
    public let meta: String
    public let action: String
    public let glyph: Glyph
    public let isDimmed: Bool

    public static func make(for status: DictationStatus,
                            shortcut: String,
                            modelName: String) -> StatusPresentation {
        switch status {
        case .loading:
            return .init(title: "Preparing model", meta: shortModelName(modelName),
                         action: "Start Dictation", glyph: .idle, isDimmed: true)
        case .idle:
            return .init(title: "Ready", meta: "\(shortcut) hold",
                         action: "Start Dictation", glyph: .idle, isDimmed: false)
        case .recording(let elapsed):
            return .init(title: "Recording", meta: elapsedLabel(elapsed),
                         action: "Stop Dictation", glyph: .recording, isDimmed: false)
        case .transcribing:
            return .init(title: "Transcribing", meta: shortModelName(modelName),
                         action: "Stop Dictation", glyph: .recording, isDimmed: false)
        case .error(let message):
            return .init(title: message, meta: "",
                         action: "Retry", glyph: .idle, isDimmed: true)
        }
    }

    /// "openai_whisper-small.en" → "small.en". Vendor prefixes are noise in a menu.
    private static func shortModelName(_ name: String) -> String {
        guard let range = name.range(of: "whisper-") else { return name }
        return String(name[range.upperBound...])
    }

    private static func elapsedLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
