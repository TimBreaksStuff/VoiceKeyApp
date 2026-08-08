import Testing
@testable import VoiceKeyCore

/// The sidebar's "This week" card: how many words were dictated this week, how
/// fast they were spoken, and how much typing that saved.
@Suite struct TranscriptStatsTests {

    // MARK: - Factories

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday, 5 August 2026, 15:13 UTC — the week began on Monday the 3rd.
    private let now = Date(timeIntervalSince1970: 1_785_942_780)

    private func record(daysAgo: Double = 0, words: Int = 1,
                        duration: TimeInterval = 0) -> Transcript {
        Transcript(text: Array(repeating: "word", count: words).joined(separator: " "),
                   date: now.addingTimeInterval(-daysAgo * 86_400),
                   duration: duration)
    }

    private func stats(_ records: [Transcript]) -> TranscriptStats {
        TranscriptStats.make(from: records, now: now, calendar: calendar)
    }

    // MARK: - Words

    @Test func wordsAddsUpEveryTranscriptDictatedThisWeek() {
        #expect(stats([record(words: 12), record(daysAgo: 1, words: 9)]).words == "21")
    }

    @Test func wordsFromAnEarlierWeekAreLeftOut() {
        #expect(stats([record(words: 12), record(daysAgo: 7, words: 9)]).words == "12")
    }

    @Test func wordsGroupsThousandsWithAComma() {
        #expect(stats([record(words: 1_284)]).words == "1,284")
    }

    @Test func aQuietWeekReadsAsZeroRatherThanAsNothingAtAll() {
        #expect(stats([]).words == "0")
        #expect(stats([record(daysAgo: 9)]).words == "0")
    }

    // MARK: - Pace

    @Test func paceIsWordsOverRecordingTime() {
        #expect(stats([record(words: 30, duration: 15)]).pace == "120 wpm")
    }

    @Test func paceTakesTheMedianSoOneOddRunDoesNotSkewIt() {
        let result = stats([record(words: 20, duration: 60),    // 20 wpm
                            record(words: 100, duration: 60),   // 100 wpm
                            record(words: 120, duration: 60)])  // 120 wpm

        #expect(result.pace == "100 wpm")
    }

    @Test func paceAveragesTheMiddleTwoWhenThereIsAnEvenNumberOfRuns() {
        #expect(stats([record(words: 100, duration: 60),
                       record(words: 120, duration: 60)]).pace == "110 wpm")
    }

    @Test func paceIgnoresRunsThatWereNeverTimed() {
        #expect(stats([record(words: 100, duration: 60), record(words: 5_000)]).pace == "100 wpm")
    }

    @Test func paceIgnoresRunsFromAnEarlierWeek() {
        #expect(stats([record(daysAgo: 7, words: 100, duration: 60)]).pace == "—")
    }

    @Test func paceIsUnknownWhenNothingWasTimed() {
        #expect(stats([record(words: 40)]).pace == "—")
    }

    // MARK: - Typing saved

    @Test func typingSavedIsTheTimeTypingWouldHaveTakenLessTheTimeSpentSpeaking() {
        // 400 words is 10 minutes of typing; they were spoken in two.
        #expect(stats([record(words: 400, duration: 120)]).typingSaved == "≈8 min")
    }

    @Test func typingSavedAddsUpEveryTimedRunOfTheWeek() {
        #expect(stats([record(words: 400, duration: 120),
                       record(daysAgo: 1, words: 400, duration: 120)]).typingSaved == "≈16 min")
    }

    @Test func aSavingUnderAMinuteSaysSoRatherThanRoundingItAway() {
        // 40 words is a minute of typing, and they took most of a minute to say.
        #expect(stats([record(words: 40, duration: 36)]).typingSaved == "<1 min")
    }

    @Test func speakingSlowerThanTypingSavesNothing() {
        #expect(stats([record(words: 40, duration: 300)]).typingSaved == "<1 min")
    }

    @Test func typingSavedIsUnknownWhenNothingWasTimed() {
        #expect(stats([record(words: 400)]).typingSaved == "—")
        #expect(stats([]).typingSaved == "—")
    }
}
