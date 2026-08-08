import AppKit
import Foundation
import VoiceKeyCore

/// Plays the two cues from `CueSound` on the default output device. The WAV
/// bytes are synthesised once and held, so a cue costs no disk and no work at
/// the moment the shortcut is pressed.
enum SoundCue {

    private static let started = sound(CueSound.start)
    private static let stopped = sound(CueSound.stop)

    static func recordingStarted() { play(started) }

    static func recordingStopped() { play(stopped) }

    private static func sound(_ tones: [CueTone]) -> NSSound? {
        NSSound(data: Data(CueSound.wav(tones)))
    }

    /// `stop()` first: an NSSound already playing ignores `play()`, and the two
    /// cues can land back to back after a very short recording.
    private static func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }
}
