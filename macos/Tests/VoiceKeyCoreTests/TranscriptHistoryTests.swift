import Testing
@testable import VoiceKeyCore

@Suite struct TranscriptHistoryTests {

    // MARK: - Factories

    private func makeHistory(transcripts: [String] = []) -> TranscriptHistory {
        transcripts.reduce(TranscriptHistory()) { $0.adding($1) }
    }

    // MARK: - Collecting transcripts

    @Test func newHistoryHasNoEntries() {
        #expect(makeHistory().entries == [])
    }

    @Test func addingPrependsSoNewestComesFirst() {
        let history = makeHistory(transcripts: ["a", "b"])

        #expect(history.entries == ["b", "a"])
    }

    @Test func addingBeyondTenEntriesDropsTheOldest() {
        let history = makeHistory(transcripts: (1...11).map(String.init))

        #expect(history.entries == (2...11).reversed().map(String.init))
    }

    @Test func addingLeavesTheOriginalHistoryUnchanged() {
        let original = makeHistory(transcripts: ["a"])

        _ = original.adding("b")

        #expect(original.entries == ["a"])
    }

    @Test func blankTranscriptsAreNotRecorded() {
        let history = makeHistory(transcripts: ["a"])

        #expect(history.adding("") == history)
        #expect(history.adding("   \n\t ") == history)
    }

    @Test func repeatingTheNewestTranscriptDoesNotCreateASecondEntry() {
        let history = makeHistory(transcripts: ["a", "b", "b"])

        #expect(history.entries == ["b", "a"])
    }

    @Test func repeatingAnOlderTranscriptIsRecordedAgain() {
        let history = makeHistory(transcripts: ["a", "b", "a"])

        #expect(history.entries == ["a", "b", "a"])
    }

    @Test func entriesPreserveTheTranscriptTextExactly() {
        let messy = "  hello\n  there  "

        #expect(makeHistory(transcripts: [messy]).entries == [messy])
    }

    // MARK: - Records

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    @Test func recordsKeepWhenEachTranscriptWasDictatedAndHowLongItTook() {
        let history = TranscriptHistory()
            .adding("hello there", at: date("2026-08-05T15:13:00Z"), duration: 4)

        #expect(history.records.count == 1)
        #expect(history.records[0].text == "hello there")
        #expect(history.records[0].date == date("2026-08-05T15:13:00Z"))
        #expect(history.records[0].duration == 4)
    }

    @Test func recordsCountWordsForTheStatsRow() {
        let history = TranscriptHistory()
            .adding("one two  three\nfour", at: date("2026-08-05T15:13:00Z"))

        #expect(history.records[0].wordCount == 4)
    }

    @Test func recordsOutliveTheTenEntriesTheMenuShows() {
        let history = (1...12).reduce(TranscriptHistory()) {
            $0.adding(String($1), at: date("2026-08-05T15:13:00Z"))
        }

        #expect(history.entries.count == 10)
        #expect(history.records.count == 12)
    }

    @Test func eachRecordCanBeRemovedOnItsOwn() {
        let history = TranscriptHistory()
            .adding("a", at: date("2026-08-05T15:13:00Z"))
            .adding("b", at: date("2026-08-05T15:14:00Z"))

        let remaining = history.removing(history.records[0].id)

        #expect(remaining.records.map(\.text) == ["a"])
    }

    @Test func removingAnUnknownRecordChangesNothing() {
        let history = TranscriptHistory().adding("a", at: date("2026-08-05T15:13:00Z"))

        #expect(history.removing(UUID()) == history)
    }

    // MARK: - Clearing

    @Test func clearingLeavesNothingBehind() {
        let cleared = makeHistory(transcripts: ["a", "b"]).cleared()

        #expect(cleared.records.isEmpty)
        #expect(cleared.entries.isEmpty)
    }

    @Test func clearingAnEmptyHistoryChangesNothing() {
        let empty = TranscriptHistory()

        #expect(empty.cleared() == empty)
    }

    @Test func isEmptyReportsWhetherThereIsAnythingToClear() {
        #expect(TranscriptHistory().isEmpty)
        #expect(!makeHistory(transcripts: ["a"]).isEmpty)
        #expect(makeHistory(transcripts: ["a"]).cleared().isEmpty)
    }

    // MARK: - Restoring

    /// Three transcripts an hour apart, newest first — as the log holds them.
    private func dated() -> TranscriptHistory {
        TranscriptHistory(records: [
            Transcript(text: "newest", date: date("2026-08-06T12:00:00Z")),
            Transcript(text: "middle", date: date("2026-08-06T11:00:00Z")),
            Transcript(text: "oldest", date: date("2026-08-06T10:00:00Z")),
        ])
    }

    @Test func aRestoredTranscriptGoesBackWhereItWas() {
        let history = dated()
        let removed = history.records[1]

        let restored = history.removing(removed.id).restoring(removed)

        #expect(restored.records.map(\.text) == ["newest", "middle", "oldest"])
    }

    @Test func aRestoredTranscriptKeepsItsIdentity() {
        let history = dated()
        let removed = history.records[0]

        #expect(history.removing(removed.id).restoring(removed).records[0] == removed)
    }

    @Test func restoringSomethingAlreadyThereChangesNothing() {
        let history = dated()

        #expect(history.restoring(history.records[0]) == history)
    }

    // MARK: - Export

    @Test func exportListsEveryTranscriptNewestFirstUnderItsTimestamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let history = TranscriptHistory(records: [
            Transcript(text: "later", date: date("2026-08-06T12:02:00Z")),
            Transcript(text: "earlier", date: date("2026-08-05T18:14:00Z")),
        ])

        #expect(history.exportText(calendar: calendar)
            == "2026-08-06 12:02\nlater\n\n2026-08-05 18:14\nearlier\n")
    }

    @Test func exportingAnEmptyHistoryProducesAnEmptyFileRatherThanAStrayBlankLine() {
        #expect(TranscriptHistory().exportText() == "")
    }

    // MARK: - Persistence

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voicekey-history-\(UUID().uuidString).json")
    }

    @Test func savedHistoryReloadsWithEveryRecordIntact() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let history = TranscriptHistory()
            .adding("a", at: date("2026-08-05T15:13:00Z"), duration: 2)
            .adding("b", at: date("2026-08-05T15:14:00Z"), duration: 3)

        try history.save(to: url)

        #expect(TranscriptHistory.load(from: url) == history)
    }

    @Test func loadingAMissingOrBrokenFileReportsNoHistoryRatherThanCrashing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptHistory.load(from: url) == nil)

        try Data("not json".utf8).write(to: url)

        #expect(TranscriptHistory.load(from: url) == nil)
    }

    // MARK: - Menu titles

    @Test func menuTitleReturnsShortTranscriptsWhole() {
        #expect(TranscriptHistory.menuTitle(for: "hello there") == "hello there")
    }

    @Test func menuTitleCollapsesWhitespaceRunsAndNewlinesIntoSingleSpaces() {
        #expect(
            TranscriptHistory.menuTitle(for: "  hello\n\n  there\tworld  ")
                == "hello there world"
        )
    }

    @Test func menuTitleTruncatesBeyondSixtyCharactersWithAnEllipsis() {
        let transcript = String(repeating: "x", count: 62)

        #expect(TranscriptHistory.menuTitle(for: transcript) == String(repeating: "x", count: 60) + "…")
    }

    @Test func menuTitleDoesNotTruncateAtExactlySixtyCharacters() {
        let transcript = String(repeating: "x", count: 60)

        #expect(TranscriptHistory.menuTitle(for: transcript) == transcript)
    }

    @Test func menuTitleCountsCharactersNotBytes() {
        let short = String(repeating: "é", count: 60)
        let long = String(repeating: "é", count: 61)

        #expect(TranscriptHistory.menuTitle(for: short) == short)
        #expect(TranscriptHistory.menuTitle(for: long) == short + "…")
    }

    @Test func menuTitleMeasuresLengthAfterCollapsingWhitespace() {
        // 20 × "ab  " + "cd" collapses to 62 characters, so it truncates at 60.
        let transcript = String(repeating: "ab  ", count: 20) + "cd"

        #expect(TranscriptHistory.menuTitle(for: transcript) == String(repeating: "ab ", count: 20) + "…")
    }
}
