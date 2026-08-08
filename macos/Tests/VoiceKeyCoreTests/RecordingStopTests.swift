import Testing
@testable import VoiceKeyCore

private let oneSecond = RecordingStop.sampleRate

@Suite("Recording stop")
struct RecordingStopTests {

    // MARK: - Stopping on silence

    @Test("silence ends the recording once speech has been heard")
    func silenceEndsRecording() {
        #expect(RecordingStop.shouldStop(stopsOnSilence: true, heardSpeech: true,
                                         silentSamples: oneSecond, totalSamples: 3 * oneSecond))
    }

    @Test("shorter silence is a pause for breath and keeps recording")
    func shortSilenceKeepsRecording() {
        #expect(!RecordingStop.shouldStop(stopsOnSilence: true, heardSpeech: true,
                                          silentSamples: oneSecond - 1,
                                          totalSamples: 3 * oneSecond))
    }

    @Test("silence before anyone has spoken is waiting, not an ending")
    func silenceBeforeSpeechIsWaiting() {
        #expect(!RecordingStop.shouldStop(stopsOnSilence: false, heardSpeech: false,
                                          silentSamples: 10 * oneSecond,
                                          totalSamples: 10 * oneSecond))
        #expect(!RecordingStop.shouldStop(stopsOnSilence: true, heardSpeech: false,
                                          silentSamples: 10 * oneSecond,
                                          totalSamples: 10 * oneSecond))
    }

    // MARK: - The setting that turns it off

    @Test("with the setting off, silence never ends the recording")
    func settingOffIgnoresSilence() {
        #expect(!RecordingStop.shouldStop(stopsOnSilence: false, heardSpeech: true,
                                          silentSamples: 60 * oneSecond,
                                          totalSamples: 90 * oneSecond))
    }

    @Test("the row carries whether silence will stop the recording")
    func rowCarriesTheState() {
        #expect(RecordingStop.label(true) == "Stop on silence — On")
        #expect(RecordingStop.label(false) == "Stop on silence — Off")
    }

    // MARK: - The cap that catches a recording nobody stopped

    @Test("five minutes ends the recording even with silence stopping turned off")
    func capEndsRecording() {
        #expect(!RecordingStop.shouldStop(stopsOnSilence: false, heardSpeech: true,
                                          silentSamples: 0,
                                          totalSamples: RecordingStop.maxSamples - 1))
        #expect(RecordingStop.shouldStop(stopsOnSilence: false, heardSpeech: true,
                                         silentSamples: 0,
                                         totalSamples: RecordingStop.maxSamples))
    }

    @Test("the cap does not wait for speech either — it is a floor under the buffer")
    func capDoesNotWaitForSpeech() {
        #expect(RecordingStop.shouldStop(stopsOnSilence: false, heardSpeech: false,
                                         silentSamples: RecordingStop.maxSamples,
                                         totalSamples: RecordingStop.maxSamples))
    }

    @Test("the cap is five minutes of 16 kHz audio")
    func capIsFiveMinutes() {
        #expect(RecordingStop.maxSamples == 5 * 60 * 16_000)
    }
}
