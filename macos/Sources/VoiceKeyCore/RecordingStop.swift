import Foundation

/// When a recording ends on its own. Two ways it can: a second of silence after
/// speech — which is the default, and what makes hold-to-talk unnecessary for a
/// single sentence — or the five-minute cap, which is there for the recording
/// nobody stopped. Pure; the recorder counts the samples and calls this.
public enum RecordingStop {

    /// What the recorders resample to, so sample counts are seconds.
    public static let sampleRate = 16_000

    /// Trailing silence that reads as "finished speaking" rather than a breath.
    public static let silenceSamples = sampleRate

    /// Five minutes. With silence stopping turned off, the only other end is a
    /// second press of the shortcut — and a shortcut can be forgotten.
    public static let maxSamples = 5 * 60 * sampleRate

    /// The settings row that turns silence stopping off, worded like the sound
    /// cues row beside it: the state is the word after the dash.
    public static func label(_ stopsOnSilence: Bool) -> String {
        "Stop on silence — \(stopsOnSilence ? "On" : "Off")"
    }

    /// - Parameters:
    ///   - silentSamples: Samples since the last speech, reset by every utterance.
    ///   - totalSamples: Everything recorded so far.
    public static func shouldStop(stopsOnSilence: Bool, heardSpeech: Bool,
                                  silentSamples: Int, totalSamples: Int) -> Bool {
        totalSamples >= maxSamples
            || (stopsOnSilence && heardSpeech && silentSamples >= silenceSamples)
    }
}
