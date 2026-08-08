import Foundation

/// Per-app dictation mode ("Power Mode"): the frontmost app decides how a
/// transcript is punctuated before it is inserted at the cursor.
public enum DictationMode: Equatable {
    /// Terminals, editors, IDEs — spoken commands should not gain a trailing period.
    case code
    /// Mail clients — sentences should end in punctuation.
    case email
    /// Everything else — the transcript is inserted verbatim.
    case standard

    /// Bundle IDs are compared lower-cased, so every entry here is lower-cased too.
    private static let codeBundleIDs: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.microsoft.vscode",
        "com.todesktop.230313mzl4w4u92",
        "com.apple.dt.xcode",
        "dev.zed.zed",
        "com.sublimetext.4",
        "com.github.githubclient",
    ]

    /// JetBrains ships one bundle ID per IDE (idea, pycharm, goland, …), so they are matched by prefix.
    private static let codeBundleIDPrefixes: [String] = [
        "com.jetbrains.",
    ]

    private static let emailBundleIDs: Set<String> = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.readdle.sparkdesktop",
        "com.superhuman.electron",
    ]

    /// Mode for the frontmost app. nil bundle ID → .standard.
    public static func mode(forBundleID bundleID: String?) -> DictationMode {
        guard let identifier = bundleID?.lowercased() else { return .standard }
        if codeBundleIDs.contains(identifier) { return .code }
        if codeBundleIDPrefixes.contains(where: identifier.hasPrefix) { return .code }
        if emailBundleIDs.contains(identifier) { return .email }
        return .standard
    }

    /// Whether a finished dictation should be typed at the cursor at all.
    ///
    /// VoiceKey never types into itself. Dictating with its own window in front
    /// pastes into whatever there has focus — the library's search field — and
    /// the list then filters down to the transcript just spoken, which reads as
    /// every earlier one having been lost. The transcript is recorded and copied
    /// instead; the row's own "Insert" button is the way back out, and it steps
    /// the app aside first.
    public static func insertsAtCursor(frontmostBundleID: String?, ownBundleID: String?) -> Bool {
        guard let own = ownBundleID?.lowercased(),
              let frontmost = frontmostBundleID?.lowercased()
        else { return true }
        return frontmost != own
    }

    /// Mode-specific transcript formatting. Pure.
    public func format(_ text: String) -> String {
        switch self {
        case .code: return Self.formattedForCode(text)
        case .email: return Self.formattedForEmail(text)
        case .standard: return text
        }
    }

    /// Drops exactly one trailing period — but leaves "…" and "..." intact, since
    /// those are dictated content rather than sentence punctuation.
    private static func formattedForCode(_ text: String) -> String {
        let trimmed = trimmingTrailingWhitespace(text)
        guard trimmed.hasSuffix(".") else { return trimmed }
        let withoutPeriod = String(trimmed.dropLast())
        guard !withoutPeriod.hasSuffix(".") else { return trimmed }
        return withoutPeriod
    }

    /// Appends a period when the sentence trails off on a letter or digit;
    /// anything already ending in punctuation (. ! ? : …) is left alone.
    private static func formattedForEmail(_ text: String) -> String {
        let trimmed = trimmingTrailingWhitespace(text)
        guard let last = trimmed.last, last.isLetter || last.isNumber else { return trimmed }
        return trimmed + "."
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        String(text.reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}
