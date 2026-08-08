using System.Text.RegularExpressions;

namespace VoiceKey.Core;

/// <summary>
/// Post-processing for raw speech-to-text output: strips disfluencies that
/// Whisper faithfully transcribes, and recognises whole-transcript non-speech
/// annotations (<c>[wind howling]</c>, <c>(music)</c>) that must never be pasted.
/// </summary>
public static class TranscriptCleaner
{
    /// <summary>Removes filler words and collapses stutter repetitions. Pure.</summary>
    public static string Clean(string text) =>
        NormalisingWhitespace(
            CollapsingImmediateRepetitions(
                RemovingFillers(
                    CapitalisingAfterSentenceInitialFillers(text))));

    /// <summary>
    /// True when the entire transcript is a non-speech annotation like
    /// <c>[wind howling]</c> or <c>(music)</c>.
    /// </summary>
    public static bool IsNonSpeechAnnotation(string text) =>
        AnnotationRegex.IsMatch(text.Trim());

    // MARK: - Stages

    /// <summary>
    /// A capitalised filler opening a sentence hands its capitalisation to the
    /// word that follows, so the filler can then be deleted like any other.
    /// </summary>
    private static string CapitalisingAfterSentenceInitialFillers(string text) =>
        SentenceInitialFillerRegex.Replace(text,
            match => match.Groups[1].Value + match.Groups[2].Value.ToUpperInvariant());

    private static string RemovingFillers(string text) =>
        FillerRegex.Replace(text, "");

    private static string CollapsingImmediateRepetitions(string text)
    {
        var collapsed = RepeatedWordRegex.Replace(text, "$1");
        return collapsed == text ? text : CollapsingImmediateRepetitions(collapsed);
    }

    private static string NormalisingWhitespace(string text)
    {
        var spaced = HorizontalWhitespaceRegex.Replace(text, " ");
        return PaddedNewlineRegex.Replace(spaced, "\n").Trim();
    }

    // MARK: - Regexes

    // Longer spellings precede their prefixes only where `\b` cannot decide;
    // the word boundary makes the order irrelevant for the rest. The alternation
    // is shared by two expressions.
    private const string FillerAlternatives = "um|uhm|umm|uh|erm|er|mhm";

    private static readonly Regex SentenceInitialFillerRegex = new(
        $@"(\A|[.!?][ \t]+|\n[ \t]*)(?i:{FillerAlternatives})\b[ \t]*(?:,|\.\.\.|…)?[ \t]*([a-z])",
        RegexOptions.Compiled);

    private static readonly Regex FillerRegex = new(
        $@"\b(?:{FillerAlternatives})\b[ \t]*(?:,|\.\.\.|…)?",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex RepeatedWordRegex = new(
        @"\b([\p{L}\p{N}']+)[ \t]+\1\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex HorizontalWhitespaceRegex = new(
        @"[ \t]+", RegexOptions.Compiled);

    private static readonly Regex PaddedNewlineRegex = new(
        @"[ \t]*\n[ \t]*", RegexOptions.Compiled);

    private static readonly Regex AnnotationRegex = new(
        @"\A(?:\[[^\[\]]+\]|\([^()]+\))\z", RegexOptions.Compiled);
}
