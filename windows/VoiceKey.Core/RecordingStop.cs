namespace VoiceKey.Core;

/// <summary>
/// When a recording ends on its own. Two ways it can: a second of silence after
/// speech — which is the default, and what makes hold-to-talk unnecessary for a
/// single sentence — or the five-minute cap, which is there for the recording
/// nobody stopped. Pure; the recorder counts the samples and calls this.
/// </summary>
public static class RecordingStop
{
    /// <summary>What the recorders resample to, so sample counts are seconds.</summary>
    public const int SampleRate = 16_000;

    /// <summary>Trailing silence that reads as "finished speaking" rather than a breath.</summary>
    public const int SilenceSamples = SampleRate;

    /// <summary>
    /// Five minutes. With silence stopping turned off, the only other end is a
    /// second press of the shortcut — and a shortcut can be forgotten.
    /// </summary>
    public const int MaxSamples = 5 * 60 * SampleRate;

    /// <summary>
    /// The settings row that turns silence stopping off, worded like the sound
    /// cues row beside it: the state is the word after the dash.
    /// </summary>
    public static string Label(bool stopsOnSilence) =>
        $"Stop on silence — {(stopsOnSilence ? "On" : "Off")}";

    /// <param name="silentSamples">Samples since the last speech, reset by every utterance.</param>
    /// <param name="totalSamples">Everything recorded so far.</param>
    public static bool ShouldStop(bool stopsOnSilence, bool heardSpeech,
                                  int silentSamples, int totalSamples) =>
        totalSamples >= MaxSamples
        || (stopsOnSilence && heardSpeech && silentSamples >= SilenceSamples);
}
