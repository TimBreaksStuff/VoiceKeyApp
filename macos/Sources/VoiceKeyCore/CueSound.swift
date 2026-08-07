import Foundation

/// One note of a cue: a pitch, held for a while.
public struct CueTone: Equatable {
    public let hertz: Double
    public let milliseconds: Int

    public init(hertz: Double, milliseconds: Int) {
        self.hertz = hertz
        self.milliseconds = milliseconds
    }
}

/// The two sounds that say VoiceKey started and stopped listening. Synthesised
/// rather than shipped as files, for the same reason the menu-bar glyph is drawn
/// in code: nothing to lose, nothing to load, and the pitches are readable here.
///
/// The pair is one interval played both ways round — E5 up to B5 to start, back
/// down to stop — so which one you heard needs no learning.
public enum CueSound {

    public static let sampleRate = 48_000

    /// Well under full scale: this sits behind whatever the user is doing.
    private static let amplitude = 0.35

    private static let fadeInSamples = sampleRate * 4 / 1000
    private static let fadeOutSamples = sampleRate * 20 / 1000

    private static let lowNote = 659.25   // E5
    private static let highNote = 987.77  // B5

    public static let start = [CueTone(hertz: lowNote, milliseconds: 70),
                               CueTone(hertz: highNote, milliseconds: 90)]

    public static let stop = [CueTone(hertz: highNote, milliseconds: 70),
                              CueTone(hertz: lowNote, milliseconds: 90)]

    /// The sidebar footer row that turns the cues off, worded like the
    /// launch-at-login row beside it: the state is the word after the dash.
    public static func label(_ enabled: Bool) -> String {
        "Sounds — \(enabled ? "On" : "Off")"
    }

    /// The tones as a canonical 16-bit mono PCM WAV, header and all.
    public static func wav(_ tones: [CueTone]) -> [UInt8] {
        let samples = tones.flatMap(render)
        let dataBytes = samples.count * 2

        var wav: [UInt8] = []
        wav.reserveCapacity(44 + dataBytes)
        wav += Array("RIFF".utf8)
        wav += bytes(Int32(36 + dataBytes))
        wav += Array("WAVE".utf8)
        wav += Array("fmt ".utf8)
        wav += bytes(Int32(16))                       // PCM header length
        wav += bytes(Int16(1))                        // PCM, uncompressed
        wav += bytes(Int16(1))                        // mono
        wav += bytes(Int32(sampleRate))
        wav += bytes(Int32(sampleRate * 2))           // bytes per second
        wav += bytes(Int16(2))                        // bytes per frame
        wav += bytes(Int16(16))                       // bits per sample
        wav += Array("data".utf8)
        wav += bytes(Int32(dataBytes))
        wav += samples.flatMap { bytes($0) }
        return wav
    }

    private static func render(_ tone: CueTone) -> [Int16] {
        let count = sampleRate * tone.milliseconds / 1000
        return (0..<count).map { index in
            Int16(sin(2 * Double.pi * tone.hertz * Double(index) / Double(sampleRate))
                  * amplitude * fade(index, count) * Double(Int16.max))
        }
    }

    /// Silent at both ends of every tone. A note that starts or stops mid-cycle
    /// is a step in the waveform, and a step is the click we are avoiding.
    private static func fade(_ index: Int, _ count: Int) -> Double {
        let rise = min(1.0, Double(index) / Double(min(fadeInSamples, count)))
        let fall = min(1.0, Double(count - 1 - index) / Double(min(fadeOutSamples, count)))
        return min(rise, fall)
    }

    private static func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
