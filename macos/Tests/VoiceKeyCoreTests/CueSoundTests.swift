import Foundation
import Testing
@testable import VoiceKeyCore

@Suite struct CueSoundTests {

    // MARK: - What the two cues sound like

    @Test func startRisesAndStopFallsSoTheDirectionAloneSaysWhichHappened() {
        #expect(CueSound.start.count == 2)
        #expect(CueSound.stop.count == 2)
        #expect(CueSound.start[1].hertz > CueSound.start[0].hertz)
        #expect(CueSound.stop[1].hertz < CueSound.stop[0].hertz)
    }

    @Test func stopIsTheSameTwoNotesAsStartInTheOtherOrder() {
        #expect(CueSound.start.map(\.hertz).sorted() == CueSound.stop.map(\.hertz).sorted())
    }

    @Test func bothCuesAreShortEnoughToPassForFeedbackRatherThanMusic() {
        #expect((1...250).contains(CueSound.start.reduce(0) { $0 + $1.milliseconds }))
        #expect((1...250).contains(CueSound.stop.reduce(0) { $0 + $1.milliseconds }))
    }

    // MARK: - The row that turns them off

    @Test func theRowCarriesWhetherTheCuesWillPlay() {
        #expect(CueSound.label(true) == "Sounds — On")
        #expect(CueSound.label(false) == "Sounds — Off")
    }

    // MARK: - The rendered WAV

    @Test func rendersACanonicalSixteenBitMonoWavAtTheStatedSampleRate() {
        let wav = CueSound.wav([CueTone(hertz: 1000, milliseconds: 100)])

        #expect(text(wav, 0) == "RIFF")
        #expect(text(wav, 8) == "WAVE")
        #expect(text(wav, 12) == "fmt ")
        #expect(int32(wav, 16) == 16)                        // PCM fmt chunk size
        #expect(int16(wav, 20) == 1)                         // format 1 = PCM
        #expect(int16(wav, 22) == 1)                         // mono
        #expect(int32(wav, 24) == Int32(CueSound.sampleRate))
        #expect(int16(wav, 34) == 16)                        // bits per sample
        #expect(text(wav, 36) == "data")
    }

    @Test func theHeadersTwoLengthsDescribeTheSamplesThatFollow() {
        let wav = CueSound.wav([CueTone(hertz: 1000, milliseconds: 100)])

        #expect(int32(wav, 4) == Int32(wav.count - 8))
        #expect(int32(wav, 40) == Int32(wav.count - 44))
    }

    @Test func holdsEveryToneForAsLongAsItAsksFor() {
        #expect(samples(CueSound.wav([CueTone(hertz: 440, milliseconds: 150)])).count
                == CueSound.sampleRate * 150 / 1000)
        #expect(samples(CueSound.wav([CueTone(hertz: 440, milliseconds: 60),
                                      CueTone(hertz: 660, milliseconds: 120)])).count
                == CueSound.sampleRate * 180 / 1000)
    }

    @Test func aTonesPitchIsThePitchItWasAskedFor() {
        let rendered = samples(CueSound.wav([CueTone(hertz: 1000, milliseconds: 200)]))

        // 1000 Hz for 0.2s crosses zero twice per cycle: 400 crossings, give or
        // take the fades at either end.
        #expect((396...404).contains(zeroCrossings(rendered)))
    }

    @Test func opensAndClosesOnSilenceSoNeitherEndClicks() {
        let rendered = samples(CueSound.wav(CueSound.start))

        #expect(rendered.first == 0)
        #expect(rendered.last == 0)
    }

    @Test func staysWellShortOfFullScaleBecauseThisIsACueNotAnAlarm() {
        let loudest = samples(CueSound.wav(CueSound.start)).map { abs(Int($0)) }.max() ?? 0

        #expect((Int(Int16.max) / 10...Int(Int16.max) / 2).contains(loudest))
    }

    // MARK: - Helpers

    private func text(_ wav: [UInt8], _ offset: Int) -> String {
        String(decoding: wav[offset..<(offset + 4)], as: UTF8.self)
    }

    private func int32(_ wav: [UInt8], _ offset: Int) -> Int32 {
        (0..<4).reduce(Int32(0)) { $0 | Int32(wav[offset + $1]) << (8 * $1) }
    }

    private func int16(_ wav: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8)
    }

    private func samples(_ wav: [UInt8]) -> [Int16] {
        stride(from: 44, to: wav.count, by: 2).map {
            Int16(bitPattern: UInt16(wav[$0]) | UInt16(wav[$0 + 1]) << 8)
        }
    }

    private func zeroCrossings(_ samples: [Int16]) -> Int {
        zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }
}
