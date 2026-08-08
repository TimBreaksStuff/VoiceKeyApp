import Testing
@testable import VoiceKeyCore

@Suite struct StatusPresentationTests {

    private func present(_ status: DictationStatus,
                         shortcut: String = "⌃⌥D",
                         model: String = "openai_whisper-small.en") -> StatusPresentation {
        StatusPresentation.make(for: status, shortcut: shortcut, modelName: model)
    }

    // MARK: - Settling

    @Test func settlingWithAWorkingShortcutIsPlainlyIdle() {
        #expect(DictationStatus.settled(shortcutIsBound: true, shortcut: "⌃⌥D") == .idle)
    }

    @Test func settlingWithAShortcutThatNeverBoundSaysSoInsteadOfClaimingReady() {
        #expect(DictationStatus.settled(shortcutIsBound: false, shortcut: "⌃⌥D")
            == .error("⌃⌥D is taken by another app"))
    }

    // MARK: - Titles

    @Test func eachStateNamesItselfInOneOrTwoWords() {
        #expect(present(.loading).title == "Preparing model")
        #expect(present(.idle).title == "Ready")
        #expect(present(.recording(elapsed: 0)).title == "Recording")
        #expect(present(.transcribing).title == "Transcribing")
    }

    @Test func errorStateShowsTheMessageAsItsTitle() {
        #expect(present(.error("Microphone access denied")).title == "Microphone access denied")
    }

    // MARK: - Meta column

    @Test func idleMetaShowsTheShortcutAndHowToUseIt() {
        #expect(present(.idle, shortcut: "⌃⌥D").meta == "⌃⌥D hold")
        #expect(present(.idle, shortcut: "⇧⌘Space").meta == "⇧⌘Space hold")
    }

    @Test func recordingMetaCountsElapsedTimeAsMinutesAndSeconds() {
        #expect(present(.recording(elapsed: 0)).meta == "0:00")
        #expect(present(.recording(elapsed: 7)).meta == "0:07")
        #expect(present(.recording(elapsed: 65)).meta == "1:05")
        #expect(present(.recording(elapsed: 600)).meta == "10:00")
    }

    @Test func recordingMetaNeverShowsNegativeTime() {
        #expect(present(.recording(elapsed: -3)).meta == "0:00")
    }

    @Test func modelStatesNameTheModelWithoutItsVendorPrefix() {
        #expect(present(.transcribing).meta == "small.en")
        #expect(present(.loading).meta == "small.en")
    }

    @Test func modelNameWithoutAVendorPrefixIsShownVerbatim() {
        #expect(present(.transcribing, model: "tiny.en").meta == "tiny.en")
    }

    @Test func errorStateHasNoMeta() {
        #expect(present(.error("Model load failed")).meta == "")
    }

    // MARK: - Action item

    @Test func actionMatchesWhatThePrimaryItemWouldDo() {
        #expect(present(.loading).action == "Start Dictation")
        #expect(present(.idle).action == "Start Dictation")
        #expect(present(.recording(elapsed: 0)).action == "Stop Dictation")
        #expect(present(.transcribing).action == "Stop Dictation")
        #expect(present(.error("nope")).action == "Retry")
    }

    // MARK: - Glyph

    @Test func onlyLiveStatesUseTheFilledGlyph() {
        #expect(present(.recording(elapsed: 0)).glyph == .recording)
        #expect(present(.transcribing).glyph == .recording)
        #expect(present(.idle).glyph == .idle)
        #expect(present(.loading).glyph == .idle)
        #expect(present(.error("nope")).glyph == .idle)
    }

    @Test func statesTheUserCannotDictateInAreDimmed() {
        #expect(present(.loading).isDimmed)
        #expect(present(.error("nope")).isDimmed)
        #expect(!present(.idle).isDimmed)
        #expect(!present(.recording(elapsed: 0)).isDimmed)
        #expect(!present(.transcribing).isDimmed)
    }
}
