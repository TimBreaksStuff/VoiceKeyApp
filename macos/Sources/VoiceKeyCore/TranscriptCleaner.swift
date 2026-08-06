import Foundation

/// Post-processing for raw speech-to-text output: strips disfluencies that
/// Whisper faithfully transcribes, and recognises whole-transcript non-speech
/// annotations (`[wind howling]`, `(music)`) that must never be pasted.
public enum TranscriptCleaner {

    /// Removes filler words and collapses stutter repetitions. Pure.
    public static func clean(_ text: String) -> String {
        normalisingWhitespace(
            collapsingImmediateRepetitions(
                removingFillers(
                    capitalisingAfterSentenceInitialFillers(text))))
    }

    /// True when the entire transcript is a non-speech annotation like
    /// `[wind howling]` or `(music)`.
    public static func isNonSpeechAnnotation(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .wholeMatch(of: #/\[[^\[\]]+\]|\([^()]+\)/#) != nil
    }

    // MARK: - Stages

    /// A capitalised filler opening a sentence hands its capitalisation to the
    /// word that follows, so the filler can then be deleted like any other.
    private static func capitalisingAfterSentenceInitialFillers(_ text: String) -> String {
        text.replacing(sentenceInitialFillerRegex) { match in
            String(match.output[1].substring ?? "") + String(match.output[2].substring ?? "").uppercased()
        }
    }

    private static func removingFillers(_ text: String) -> String {
        text.replacing(fillerRegex, with: "")
    }

    private static func collapsingImmediateRepetitions(_ text: String) -> String {
        let collapsed = repeatedWordRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "$1"
        )
        return collapsed == text ? text : collapsingImmediateRepetitions(collapsed)
    }

    private static func normalisingWhitespace(_ text: String) -> String {
        text.replacing(#/[ \t]+/#, with: " ")
            .replacing(#/[ \t]*\n[ \t]*/#, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regexes

    // Longer spellings precede their prefixes only where `\b` cannot decide;
    // the word boundary makes the order irrelevant for the rest. The alternation
    // is shared by two regexes, so they are built from strings (literals cannot
    // interpolate); the patterns are constant, so the force-try cannot fail once
    // any test has run.
    private static let fillerAlternatives = "um|uhm|umm|uh|erm|er|mhm"

    private static let sentenceInitialFillerRegex = try! Regex(
        #"(\A|[.!?][ \t]+|\n[ \t]*)(?i:\#(fillerAlternatives))\b[ \t]*(?:,|\.\.\.|…)?[ \t]*([a-z])"#
    )

    private static let fillerRegex = try! Regex(
        #"\b(?:\#(fillerAlternatives))\b[ \t]*(?:,|\.\.\.|…)?"#
    ).ignoresCase()

    // NSRegularExpression, not Swift Regex: the Swift engine matches
    // backreferences case-sensitively even under (?i), so "The the" would
    // survive (verified on Swift 6.2.3).
    private static let repeatedWordRegex = try! NSRegularExpression(
        pattern: #"\b([\p{L}\p{N}']+)[ \t]+\1\b"#,
        options: [.caseInsensitive]
    )
}
