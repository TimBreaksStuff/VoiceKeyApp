using System.Globalization;

namespace VoiceKey.Core.Tests;

public class TranscriptHistoryTests
{
    // MARK: - Factories

    private static TranscriptHistory MakeHistory(params string[] transcripts) =>
        transcripts.Aggregate(new TranscriptHistory(), (history, text) => history.Adding(text));

    private static DateTimeOffset Date(string iso) =>
        DateTimeOffset.Parse(iso, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);

    // MARK: - Collecting transcripts

    [Fact]
    public void NewHistoryHasNoEntries()
    {
        Assert.Empty(MakeHistory().Entries);
    }

    [Fact]
    public void AddingPrependsSoNewestComesFirst()
    {
        Assert.Equal(["b", "a"], MakeHistory("a", "b").Entries);
    }

    [Fact]
    public void AddingBeyondTenEntriesDropsTheOldest()
    {
        var history = MakeHistory(Enumerable.Range(1, 11).Select(n => n.ToString()).ToArray());

        Assert.Equal(Enumerable.Range(2, 10).Reverse().Select(n => n.ToString()), history.Entries);
    }

    [Fact]
    public void AddingLeavesTheOriginalHistoryUnchanged()
    {
        var original = MakeHistory("a");

        original.Adding("b");

        Assert.Equal(["a"], original.Entries);
    }

    [Fact]
    public void BlankTranscriptsAreNotRecorded()
    {
        var history = MakeHistory("a");

        Assert.Equal(history, history.Adding(""));
        Assert.Equal(history, history.Adding("   \n\t "));
    }

    [Fact]
    public void RepeatingTheNewestTranscriptDoesNotCreateASecondEntry()
    {
        Assert.Equal(["b", "a"], MakeHistory("a", "b", "b").Entries);
    }

    [Fact]
    public void RepeatingAnOlderTranscriptIsRecordedAgain()
    {
        Assert.Equal(["a", "b", "a"], MakeHistory("a", "b", "a").Entries);
    }

    [Fact]
    public void EntriesPreserveTheTranscriptTextExactly()
    {
        const string messy = "  hello\n  there  ";

        Assert.Equal([messy], MakeHistory(messy).Entries);
    }

    // MARK: - Records

    [Fact]
    public void RecordsKeepWhenEachTranscriptWasDictatedAndHowLongItTook()
    {
        var history = new TranscriptHistory()
            .Adding("hello there", Date("2026-08-05T15:13:00Z"), TimeSpan.FromSeconds(4));

        var record = Assert.Single(history.Records);
        Assert.Equal("hello there", record.Text);
        Assert.Equal(Date("2026-08-05T15:13:00Z"), record.Date);
        Assert.Equal(TimeSpan.FromSeconds(4), record.Duration);
    }

    [Fact]
    public void RecordsCountWordsForTheStatsRow()
    {
        var history = new TranscriptHistory()
            .Adding("one two  three\nfour", Date("2026-08-05T15:13:00Z"));

        Assert.Equal(4, history.Records[0].WordCount);
    }

    [Fact]
    public void RecordsOutliveTheTenEntriesTheMenuShows()
    {
        var history = Enumerable.Range(1, 12).Aggregate(new TranscriptHistory(),
            (acc, n) => acc.Adding(n.ToString(), Date("2026-08-05T15:13:00Z")));

        Assert.Equal(10, history.Entries.Count);
        Assert.Equal(12, history.Records.Count);
    }

    [Fact]
    public void EachRecordCanBeRemovedOnItsOwn()
    {
        var history = new TranscriptHistory()
            .Adding("a", Date("2026-08-05T15:13:00Z"))
            .Adding("b", Date("2026-08-05T15:14:00Z"));

        var remaining = history.Removing(history.Records[0].Id);

        Assert.Equal(["a"], remaining.Records.Select(record => record.Text));
    }

    [Fact]
    public void RemovingAnUnknownRecordChangesNothing()
    {
        var history = new TranscriptHistory().Adding("a", Date("2026-08-05T15:13:00Z"));

        Assert.Equal(history, history.Removing(Guid.NewGuid()));
    }

    // MARK: - Clearing

    [Fact]
    public void ClearingLeavesNothingBehind()
    {
        var cleared = MakeHistory("a", "b").Cleared();

        Assert.Empty(cleared.Records);
        Assert.Empty(cleared.Entries);
    }

    [Fact]
    public void ClearingLeavesTheOriginalHistoryUnchanged()
    {
        var original = MakeHistory("a", "b");

        original.Cleared();

        Assert.Equal(2, original.Records.Count);
    }

    [Fact]
    public void ClearingAnEmptyHistoryChangesNothing()
    {
        var empty = new TranscriptHistory();

        Assert.Equal(empty, empty.Cleared());
    }

    [Fact]
    public void IsEmptyReportsWhetherThereIsAnythingToClear()
    {
        Assert.True(new TranscriptHistory().IsEmpty);
        Assert.False(MakeHistory("a").IsEmpty);
        Assert.True(MakeHistory("a").Cleared().IsEmpty);
    }

    // MARK: - Restoring

    /// <summary>Three transcripts an hour apart, newest first — as the log holds them.</summary>
    private static TranscriptHistory Dated() =>
        new([
            new Transcript("newest", Date("2026-08-06T12:00:00Z")),
            new Transcript("middle", Date("2026-08-06T11:00:00Z")),
            new Transcript("oldest", Date("2026-08-06T10:00:00Z")),
        ]);

    [Fact]
    public void ARestoredTranscriptGoesBackWhereItWas()
    {
        var history = Dated();
        var removed = history.Records[1];

        var restored = history.Removing(removed.Id).Restoring(removed);

        Assert.Equal(["newest", "middle", "oldest"], restored.Records.Select(record => record.Text));
    }

    [Fact]
    public void ARestoredTranscriptKeepsItsIdentity()
    {
        var history = Dated();
        var removed = history.Records[0];

        Assert.Equal(removed, history.Removing(removed.Id).Restoring(removed).Records[0]);
    }

    [Fact]
    public void RestoringSomethingAlreadyThereChangesNothing()
    {
        var history = Dated();

        Assert.Equal(history, history.Restoring(history.Records[0]));
    }

    // MARK: - Export

    [Fact]
    public void ExportListsEveryTranscriptNewestFirstUnderItsTimestamp()
    {
        var history = new TranscriptHistory([
            new Transcript("later", new DateTimeOffset(2026, 8, 6, 12, 2, 0, TimeSpan.Zero)),
            new Transcript("earlier", new DateTimeOffset(2026, 8, 5, 18, 14, 0, TimeSpan.Zero)),
        ]);

        Assert.Equal("2026-08-06 12:02\nlater\n\n2026-08-05 18:14\nearlier\n",
            history.ExportText(TimeZoneInfo.Utc));
    }

    [Fact]
    public void ExportingAnEmptyHistoryProducesAnEmptyFileRatherThanAStrayBlankLine()
    {
        Assert.Equal("", new TranscriptHistory().ExportText(TimeZoneInfo.Utc));
    }

    // MARK: - Persistence

    private static string TemporaryPath() =>
        Path.Combine(Path.GetTempPath(), $"voicekey-history-{Guid.NewGuid()}.json");

    [Fact]
    public void SavedHistoryReloadsWithEveryRecordIntact()
    {
        var path = TemporaryPath();
        try
        {
            var history = new TranscriptHistory()
                .Adding("a", Date("2026-08-05T15:13:00Z"), TimeSpan.FromSeconds(2))
                .Adding("b", Date("2026-08-05T15:14:00Z"), TimeSpan.FromSeconds(3));

            history.Save(path);

            Assert.Equal(history, TranscriptHistory.Load(path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void LoadingAMissingOrBrokenFileReportsNoHistoryRatherThanCrashing()
    {
        var path = TemporaryPath();
        try
        {
            Assert.Null(TranscriptHistory.Load(path));

            File.WriteAllText(path, "not json");

            Assert.Null(TranscriptHistory.Load(path));
        }
        finally { File.Delete(path); }
    }

    // MARK: - Menu titles

    [Fact]
    public void MenuTitleReturnsShortTranscriptsWhole()
    {
        Assert.Equal("hello there", TranscriptHistory.MenuTitle("hello there"));
    }

    [Fact]
    public void MenuTitleCollapsesWhitespaceRunsAndNewlinesIntoSingleSpaces()
    {
        Assert.Equal("hello there world", TranscriptHistory.MenuTitle("  hello\n\n  there\tworld  "));
    }

    [Fact]
    public void MenuTitleTruncatesBeyondSixtyCharactersWithAnEllipsis()
    {
        Assert.Equal(new string('x', 60) + "…", TranscriptHistory.MenuTitle(new string('x', 62)));
    }

    [Fact]
    public void MenuTitleDoesNotTruncateAtExactlySixtyCharacters()
    {
        var transcript = new string('x', 60);

        Assert.Equal(transcript, TranscriptHistory.MenuTitle(transcript));
    }

    [Fact]
    public void MenuTitleCountsCharactersNotBytes()
    {
        var shortText = new string('é', 60);
        var longText = new string('é', 61);

        Assert.Equal(shortText, TranscriptHistory.MenuTitle(shortText));
        Assert.Equal(shortText + "…", TranscriptHistory.MenuTitle(longText));
    }

    [Fact]
    public void MenuTitleMeasuresLengthAfterCollapsingWhitespace()
    {
        // 20 × "ab  " + "cd" collapses to 62 characters, so it truncates at 60.
        var transcript = string.Concat(Enumerable.Repeat("ab  ", 20)) + "cd";

        Assert.Equal(string.Concat(Enumerable.Repeat("ab ", 20)) + "…",
            TranscriptHistory.MenuTitle(transcript));
    }
}
