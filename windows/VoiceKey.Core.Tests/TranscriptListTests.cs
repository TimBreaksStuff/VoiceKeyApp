namespace VoiceKey.Core.Tests;

/// <summary>The main window's list: transcripts grouped by the day they were dictated.</summary>
public class TranscriptListTests
{
    // MARK: - Factories

    private static readonly TimeZoneInfo Zone = TimeZoneInfo.Utc;

    /// <summary>Wednesday, 5 August 2026, 15:13 UTC.</summary>
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_785_942_780);

    private static Transcript Record(string text = "word", double hoursAgo = 0) =>
        new(text, Now.AddHours(-hoursAgo));

    private static TranscriptList List(params Transcript[] records) =>
        TranscriptList.Make(records, Now, Zone);

    private static TranscriptList Search(string query, params Transcript[] records) =>
        TranscriptList.Make(records, Now, Zone, query);

    private static TranscriptList Sorted(TranscriptSort sort, params Transcript[] records) =>
        TranscriptList.Make(records, Now, Zone, sort: sort);

    // MARK: - Grouping

    [Fact]
    public void TranscriptsFromTheSameDayShareOneGroup()
    {
        var groups = List(Record(hoursAgo: 1), Record(hoursAgo: 2)).Groups;

        Assert.Single(groups);
        Assert.Equal(2, groups[0].Rows.Count);
    }

    [Fact]
    public void DaysRunNewestFirstAndSoDoTheRowsInsideThem()
    {
        var groups = List(Record("old", hoursAgo: 20),
                          Record("newest", hoursAgo: 1),
                          Record("earlier today", hoursAgo: 3)).Groups;

        Assert.Equal(["Today", "Yesterday"], groups.Select(group => group.Label));
        Assert.Equal(["newest", "earlier today"], groups[0].Rows.Select(row => row.Text));
        Assert.Equal(["old"], groups[1].Rows.Select(row => row.Text));
    }

    [Fact]
    public void DaysBeforeYesterdayAreNamedByTheirWeekdayAndDate()
    {
        Assert.Equal(["Today", "Sun 2 August"],
            List(Record(), Record(hoursAgo: 72)).Groups.Select(group => group.Label));
    }

    [Fact]
    public void ADayInAnEarlierYearKeepsItsYearSoItCannotBeMisread()
    {
        Assert.Equal("Tue 1 July 2025", List(Record(hoursAgo: 24 * 400)).Groups[^1].Label);
    }

    // MARK: - Group meta

    [Fact]
    public void AGroupCountsItsTranscriptsAndTheirWords()
    {
        var groups = List(Record("one two three"), Record("four five")).Groups;

        Assert.Equal("2 transcripts · 5 words", groups[0].Meta);
    }

    [Fact]
    public void ASingleTranscriptReadsInTheSingular()
    {
        Assert.Equal("1 transcript · 1 word", List(Record("solo")).Groups[0].Meta);
    }

    [Fact]
    public void GroupWordCountsAreGroupedWithACommaOnceTheyRunLong()
    {
        var many = Record(string.Join(" ", Enumerable.Repeat("word", 2_140)));

        Assert.Equal("1 transcript · 2,140 words", List(many).Groups[0].Meta);
    }

    // MARK: - Rows

    [Fact]
    public void EveryRowShowsTheTimeItWasDictated()
    {
        Assert.Equal("03:13 AM", List(Record(hoursAgo: 12)).Groups[0].Rows[0].Time);
    }

    [Fact]
    public void EveryRowCarriesItsOwnWordCount()
    {
        Assert.Equal("3 words", List(Record("one two three")).Groups[0].Rows[0].Words);
    }

    [Fact]
    public void AOneWordTranscriptCountsItselfInTheSingular()
    {
        Assert.Equal("1 word", List(Record("solo")).Groups[0].Rows[0].Words);
    }

    [Fact]
    public void ARowsWordCountIsGroupedWithACommaOnceItRunsLong()
    {
        var many = Record(string.Join(" ", Enumerable.Repeat("word", 2_140)));

        Assert.Equal("2,140 words", List(many).Groups[0].Rows[0].Words);
    }

    [Fact]
    public void RowsCarryTheirRecordIdSoActionsCanFindThemAgain()
    {
        var transcript = Record();

        Assert.Equal(transcript.Id, List(transcript).Groups[0].Rows[0].Id);
    }

    [Fact]
    public void RowTextIsTheTranscriptVerbatimIncludingItsParagraphs()
    {
        var multiline = Record("Hey Billy,\n\nHow's it going?");

        Assert.Equal("Hey Billy,\n\nHow's it going?", List(multiline).Groups[0].Rows[0].Text);
    }

    // MARK: - Nothing to show

    [Fact]
    public void AnEmptyHistoryHasNoGroupsAtAllSoTheEmptyStateCanTakeTheScreen()
    {
        var list = List();

        Assert.Empty(list.Groups);
        Assert.True(list.IsEmpty);
    }

    [Fact]
    public void ADayWithNothingInItIsNotGivenAHeading()
    {
        var list = List(Record(hoursAgo: 20));

        Assert.Equal(["Yesterday"], list.Groups.Select(group => group.Label));
        Assert.False(list.IsEmpty);
    }

    // MARK: - Search

    [Fact]
    public void SearchKeepsOnlyTheTranscriptsThatContainTheQuery()
    {
        var list = Search("deck", Record("send me the deck"), Record("book the dentist"));

        Assert.Equal(["send me the deck"], list.Groups[0].Rows.Select(row => row.Text));
    }

    [Fact]
    public void SearchIgnoresCaseSoTheUserNeedNotMatchTheTranscript()
    {
        Assert.Single(Search("DECK", Record("send me the deck")).Groups[0].Rows);
    }

    [Fact]
    public void SearchIgnoresSurroundingWhitespaceInTheQuery()
    {
        Assert.Single(Search("  deck  ", Record("send me the deck")).Groups[0].Rows);
    }

    [Fact]
    public void ADayLeftWithNoMatchesDropsOutOfTheList()
    {
        var list = Search("deck", Record("send me the deck"), Record("dentist", hoursAgo: 20));

        Assert.Equal(["Today"], list.Groups.Select(group => group.Label));
    }

    [Fact]
    public void AGroupCountsWhatTheSearchLeftRatherThanTheWholeDay()
    {
        var list = Search("deck", Record("the deck"), Record("the dentist"));

        Assert.Equal("1 transcript · 2 words", list.Groups[0].Meta);
    }

    [Fact]
    public void ASearchThatMatchesNothingLeavesAnEmptyList()
    {
        Assert.True(Search("kombucha", Record("the deck")).IsEmpty);
    }

    [Fact]
    public void AnEmptyQueryFiltersNothingOut()
    {
        Assert.Single(Search("   ", Record("the deck")).Groups[0].Rows);
    }

    // MARK: - Sort

    [Fact]
    public void OldestFirstTurnsBothTheDaysAndTheirRowsAround()
    {
        var groups = Sorted(TranscriptSort.Oldest,
                            Record("old", hoursAgo: 20),
                            Record("newest", hoursAgo: 1),
                            Record("earlier today", hoursAgo: 3)).Groups;

        Assert.Equal(["Yesterday", "Today"], groups.Select(group => group.Label));
        Assert.Equal(["earlier today", "newest"], groups[^1].Rows.Select(row => row.Text));
    }

    [Fact]
    public void LongestFirstOrdersEachDayByWordCountAndLeavesTheDaysNewestFirst()
    {
        var groups = Sorted(TranscriptSort.Longest,
                            Record("yesterday", hoursAgo: 20),
                            Record("one", hoursAgo: 1),
                            Record("one two three", hoursAgo: 3)).Groups;

        Assert.Equal(["Today", "Yesterday"], groups.Select(group => group.Label));
        Assert.Equal(["one two three", "one"], groups[0].Rows.Select(row => row.Text));
    }

    [Fact]
    public void EquallyLongTranscriptsStayNewestFirst()
    {
        var groups = Sorted(TranscriptSort.Longest,
                            Record("older", hoursAgo: 3),
                            Record("newer", hoursAgo: 1)).Groups;

        Assert.Equal(["newer", "older"], groups[0].Rows.Select(row => row.Text));
    }

    // MARK: - The status bar's storage line

    [Fact]
    public void TheStorageLineSaysHowMuchIsHeldAndThatNoneOfItLeaves()
    {
        Assert.Equal("128 transcripts stored on this machine · nothing is uploaded",
            TranscriptList.StorageLine(128));
    }

    [Fact]
    public void TheStorageLineReadsInTheSingularForOne()
    {
        Assert.Equal("1 transcript stored on this machine · nothing is uploaded",
            TranscriptList.StorageLine(1));
    }

    [Fact]
    public void TheStorageLineGroupsThousandsWithAComma()
    {
        Assert.StartsWith("1,280 transcripts", TranscriptList.StorageLine(1_280));
    }
}
