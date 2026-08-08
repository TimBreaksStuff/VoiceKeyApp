import Testing
@testable import VoiceKeyCore

/// The main window's list: transcripts grouped by the day they were dictated.
@Suite struct TranscriptListTests {

    // MARK: - Factories

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday, 5 August 2026, 15:13 UTC.
    private let now = Date(timeIntervalSince1970: 1_785_942_780)

    private func record(_ text: String = "word", hoursAgo: Double = 0) -> Transcript {
        Transcript(text: text, date: now.addingTimeInterval(-hoursAgo * 3_600))
    }

    private func list(_ records: [Transcript]) -> TranscriptList {
        TranscriptList.make(from: records, now: now, calendar: calendar)
    }

    private func search(_ query: String, _ records: [Transcript]) -> TranscriptList {
        TranscriptList.make(from: records, now: now, calendar: calendar, query: query)
    }

    private func sorted(_ sort: TranscriptList.Sort, _ records: [Transcript]) -> TranscriptList {
        TranscriptList.make(from: records, now: now, calendar: calendar, sort: sort)
    }

    // MARK: - Grouping

    @Test func transcriptsFromTheSameDayShareOneGroup() {
        let groups = list([record(hoursAgo: 1), record(hoursAgo: 2)]).groups

        #expect(groups.count == 1)
        #expect(groups[0].rows.count == 2)
    }

    @Test func daysRunNewestFirstAndSoDoTheRowsInsideThem() {
        let groups = list([record("old", hoursAgo: 20),
                           record("newest", hoursAgo: 1),
                           record("earlier today", hoursAgo: 3)]).groups

        #expect(groups.map(\.label) == ["Today", "Yesterday"])
        #expect(groups[0].rows.map(\.text) == ["newest", "earlier today"])
        #expect(groups[1].rows.map(\.text) == ["old"])
    }

    @Test func daysBeforeYesterdayAreNamedByTheirWeekdayAndDate() {
        #expect(list([record(), record(hoursAgo: 72)]).groups.map(\.label)
            == ["Today", "Sun 2 August"])
    }

    @Test func aDayInAnEarlierYearKeepsItsYearSoItCannotBeMisread() {
        #expect(list([record(hoursAgo: 24 * 400)]).groups.last?.label == "Tue 1 July 2025")
    }

    // MARK: - Group meta

    @Test func aGroupCountsItsTranscriptsAndTheirWords() {
        let groups = list([record("one two three"), record("four five")]).groups

        #expect(groups[0].meta == "2 transcripts · 5 words")
    }

    @Test func aSingleTranscriptReadsInTheSingular() {
        #expect(list([record("solo")]).groups[0].meta == "1 transcript · 1 word")
    }

    @Test func groupWordCountsAreGroupedWithACommaOnceTheyRunLong() {
        let long = record(Array(repeating: "word", count: 2_140).joined(separator: " "))

        #expect(list([long]).groups[0].meta == "1 transcript · 2,140 words")
    }

    // MARK: - Rows

    @Test func everyRowShowsTheTimeItWasDictated() {
        #expect(list([record(hoursAgo: 12)]).groups[0].rows[0].time == "03:13 AM")
    }

    @Test func everyRowCarriesItsOwnWordCount() {
        #expect(list([record("one two three")]).groups[0].rows[0].words == "3 words")
    }

    @Test func aOneWordTranscriptCountsItselfInTheSingular() {
        #expect(list([record("solo")]).groups[0].rows[0].words == "1 word")
    }

    @Test func aRowsWordCountIsGroupedWithACommaOnceItRunsLong() {
        let long = record(Array(repeating: "word", count: 2_140).joined(separator: " "))

        #expect(list([long]).groups[0].rows[0].words == "2,140 words")
    }

    @Test func rowsCarryTheirRecordIdSoActionsCanFindThemAgain() {
        let transcript = record()

        #expect(list([transcript]).groups[0].rows[0].id == transcript.id)
    }

    @Test func rowTextIsTheTranscriptVerbatimIncludingItsParagraphs() {
        let multiline = record("Hey Billy,\n\nHow's it going?")

        #expect(list([multiline]).groups[0].rows[0].text == "Hey Billy,\n\nHow's it going?")
    }

    // MARK: - Nothing to show

    @Test func anEmptyHistoryHasNoGroupsAtAllSoTheEmptyStateCanTakeTheScreen() {
        let list = list([])

        #expect(list.groups.isEmpty)
        #expect(list.isEmpty)
    }

    @Test func aDayWithNothingInItIsNotGivenAHeading() {
        let list = list([record(hoursAgo: 20)])

        #expect(list.groups.map(\.label) == ["Yesterday"])
        #expect(!list.isEmpty)
    }

    // MARK: - Search

    @Test func searchKeepsOnlyTheTranscriptsThatContainTheQuery() {
        let list = search("deck", [record("send me the deck"), record("book the dentist")])

        #expect(list.groups[0].rows.map(\.text) == ["send me the deck"])
    }

    @Test func searchIgnoresCaseSoTheUserNeedNotMatchTheTranscript() {
        #expect(search("DECK", [record("send me the deck")]).groups[0].rows.count == 1)
    }

    @Test func searchIgnoresSurroundingWhitespaceInTheQuery() {
        #expect(search("  deck  ", [record("send me the deck")]).groups[0].rows.count == 1)
    }

    @Test func aDayLeftWithNoMatchesDropsOutOfTheList() {
        let list = search("deck", [record("send me the deck"), record("dentist", hoursAgo: 20)])

        #expect(list.groups.map(\.label) == ["Today"])
    }

    @Test func aGroupCountsWhatTheSearchLeftRatherThanTheWholeDay() {
        let list = search("deck", [record("the deck"), record("the dentist")])

        #expect(list.groups[0].meta == "1 transcript · 2 words")
    }

    @Test func aSearchThatMatchesNothingLeavesAnEmptyList() {
        #expect(search("kombucha", [record("the deck")]).isEmpty)
    }

    @Test func anEmptyQueryFiltersNothingOut() {
        #expect(search("   ", [record("the deck")]).groups[0].rows.count == 1)
    }

    // MARK: - Sort

    @Test func oldestFirstTurnsBothTheDaysAndTheirRowsAround() {
        let groups = sorted(.oldest, [record("old", hoursAgo: 20),
                                      record("newest", hoursAgo: 1),
                                      record("earlier today", hoursAgo: 3)]).groups

        #expect(groups.map(\.label) == ["Yesterday", "Today"])
        #expect(groups.last?.rows.map(\.text) == ["earlier today", "newest"])
    }

    @Test func longestFirstOrdersEachDayByWordCountAndLeavesTheDaysNewestFirst() {
        let groups = sorted(.longest, [record("yesterday", hoursAgo: 20),
                                       record("one", hoursAgo: 1),
                                       record("one two three", hoursAgo: 3)]).groups

        #expect(groups.map(\.label) == ["Today", "Yesterday"])
        #expect(groups[0].rows.map(\.text) == ["one two three", "one"])
    }

    @Test func equallyLongTranscriptsStayNewestFirst() {
        let groups = sorted(.longest, [record("older", hoursAgo: 3),
                                       record("newer", hoursAgo: 1)]).groups

        #expect(groups[0].rows.map(\.text) == ["newer", "older"])
    }

    // MARK: - The status bar's storage line

    @Test func theStorageLineSaysHowMuchIsHeldAndThatNoneOfItLeaves() {
        #expect(TranscriptList.storageLine(count: 128)
            == "128 transcripts stored on this machine · nothing is uploaded")
    }

    @Test func theStorageLineReadsInTheSingularForOne() {
        #expect(TranscriptList.storageLine(count: 1)
            == "1 transcript stored on this machine · nothing is uploaded")
    }

    @Test func theStorageLineGroupsThousandsWithAComma() {
        #expect(TranscriptList.storageLine(count: 1_280).hasPrefix("1,280 transcripts"))
    }
}
