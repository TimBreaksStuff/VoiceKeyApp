import Testing
@testable import VoiceKeyCore

/// The main window's date line, engine pill, and permission popover.
@Suite struct WindowPresentationTests {

    // MARK: - Factories

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday, 5 August 2026, 15:13 UTC.
    private let now = Date(timeIntervalSince1970: 1_785_942_780)

    private func presentation(status: DictationStatus = .idle,
                              microphone: Grant = .granted,
                              accessibility: Grant = .granted,
                              model: Grant = .granted) -> WindowPresentation {
        WindowPresentation.make(status: status, now: now, calendar: calendar,
                                microphone: microphone, accessibility: accessibility, model: model)
    }

    // MARK: - Header

    @Test func theDateLineNamesTheWeekdayAndTheDay() {
        #expect(presentation().dateLine == "Wednesday, 5 August")
    }

    // MARK: - The engine pill

    @Test func thePillFollowsWhatTheAppIsDoing() {
        #expect(presentation(status: .idle).pill.label == "Ready")
        #expect(presentation(status: .recording(elapsed: 3)).pill.label == "Listening…")
        #expect(presentation(status: .transcribing).pill.label == "Transcribing…")
        #expect(presentation(status: .loading).pill.label == "Preparing…")
    }

    @Test func eachStateHasItsOwnToneSoTheColourCanBeReadWithoutTheWord() {
        #expect(presentation(status: .idle).pill.tone == .ready)
        #expect(presentation(status: .recording(elapsed: 3)).pill.tone == .listening)
        #expect(presentation(status: .transcribing).pill.tone == .working)
        #expect(presentation(status: .loading).pill.tone == .working)
    }

    @Test func anErrorPillCarriesTheMessageItself() {
        let pill = presentation(status: .error("Microphone blocked")).pill

        #expect(pill.label == "Microphone blocked")
        #expect(pill.tone == .blocked)
    }

    @Test func onlyAnErrorPillIsWorthClickingThrough() {
        #expect(presentation(status: .error("Microphone blocked")).pill.isActionable)
        #expect(!presentation(status: .idle).pill.isActionable)
        #expect(!presentation(status: .recording(elapsed: 1)).pill.isActionable)
    }

    // MARK: - Permissions

    @Test func everyPermissionIsListedWithItsState() {
        #expect(presentation().permissions.map(\.text)
                    == ["microphone · granted", "accessibility · granted", "model · loaded"])
    }

    @Test func aMissingGrantSaysSoAndAsksForAttention() {
        let lines = presentation(microphone: .denied, accessibility: .unknown, model: .pending).permissions

        #expect(lines.map(\.text)
                    == ["microphone · denied", "accessibility · not granted", "model · loading"])
        #expect(lines.map(\.needsAttention) == [true, true, true])
    }

    @Test func grantedPermissionsAskForNothing() {
        #expect(presentation().permissions.map(\.needsAttention) == [false, false, false])
    }

    @Test func eachLineKnowsWhichSubjectItSpeaksForSoItCanBeActedOn() {
        #expect(presentation().permissions.map(\.subject) == [.microphone, .accessibility, .model])
    }

    // MARK: - The onboarding strip

    @Test func theOnboardingStripIsThereForSomeoneWhoHasNotDictatedYet() {
        #expect(WindowPresentation.showsOnboarding(dismissed: false, transcripts: 0))
    }

    @Test func dismissingTheStripKeepsItAway() {
        #expect(!WindowPresentation.showsOnboarding(dismissed: true, transcripts: 0))
    }

    @Test func theStripRetiresItselfAfterTheThirdDictation() {
        #expect(WindowPresentation.showsOnboarding(dismissed: false, transcripts: 2))
        #expect(!WindowPresentation.showsOnboarding(dismissed: false, transcripts: 3))
    }
}
