namespace VoiceKey.Core.Tests;

/// <summary>
/// The sidebar's "This week" card: how many words were dictated this week, how
/// fast they were spoken, and how much typing that saved.
/// </summary>
public class TranscriptStatsTests
{
    // MARK: - Factories

    private static readonly TimeZoneInfo Zone = TimeZoneInfo.Utc;

    /// <summary>Wednesday, 5 August 2026, 15:13 UTC — the week began on Monday the 3rd.</summary>
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_785_942_780);

    private static Transcript Record(double daysAgo = 0, int words = 1, double duration = 0) =>
        new(string.Join(" ", Enumerable.Repeat("word", words)),
            Now.AddDays(-daysAgo), TimeSpan.FromSeconds(duration));

    private static TranscriptStats Stats(params Transcript[] records) =>
        TranscriptStats.Make(records, Now, Zone);

    // MARK: - Words

    [Fact]
    public void WordsAddsUpEveryTranscriptDictatedThisWeek()
    {
        Assert.Equal("21", Stats(Record(words: 12), Record(daysAgo: 1, words: 9)).Words);
    }

    [Fact]
    public void WordsFromAnEarlierWeekAreLeftOut()
    {
        Assert.Equal("12", Stats(Record(words: 12), Record(daysAgo: 7, words: 9)).Words);
    }

    [Fact]
    public void WordsGroupsThousandsWithAComma()
    {
        Assert.Equal("1,284", Stats(Record(words: 1_284)).Words);
    }

    [Fact]
    public void AQuietWeekReadsAsZeroRatherThanAsNothingAtAll()
    {
        Assert.Equal("0", Stats().Words);
        Assert.Equal("0", Stats(Record(daysAgo: 9)).Words);
    }

    // MARK: - Pace

    [Fact]
    public void PaceIsWordsOverRecordingTime()
    {
        Assert.Equal("120 wpm", Stats(Record(words: 30, duration: 15)).Pace);
    }

    [Fact]
    public void PaceTakesTheMedianSoOneOddRunDoesNotSkewIt()
    {
        var stats = Stats(Record(words: 20, duration: 60),    // 20 wpm
                          Record(words: 100, duration: 60),   // 100 wpm
                          Record(words: 120, duration: 60));  // 120 wpm

        Assert.Equal("100 wpm", stats.Pace);
    }

    [Fact]
    public void PaceAveragesTheMiddleTwoWhenThereIsAnEvenNumberOfRuns()
    {
        Assert.Equal("110 wpm", Stats(Record(words: 100, duration: 60),
                                      Record(words: 120, duration: 60)).Pace);
    }

    [Fact]
    public void PaceIgnoresRunsThatWereNeverTimed()
    {
        Assert.Equal("100 wpm", Stats(Record(words: 100, duration: 60),
                                      Record(words: 5_000)).Pace);
    }

    [Fact]
    public void PaceIgnoresRunsFromAnEarlierWeek()
    {
        Assert.Equal("—", Stats(Record(daysAgo: 7, words: 100, duration: 60)).Pace);
    }

    [Fact]
    public void PaceIsUnknownWhenNothingWasTimed()
    {
        Assert.Equal("—", Stats(Record(words: 40)).Pace);
    }

    // MARK: - Typing saved

    [Fact]
    public void TypingSavedIsTheTimeTypingWouldHaveTakenLessTheTimeSpentSpeaking()
    {
        // 400 words is 10 minutes of typing; they were spoken in two.
        Assert.Equal("≈8 min", Stats(Record(words: 400, duration: 120)).TypingSaved);
    }

    [Fact]
    public void TypingSavedAddsUpEveryTimedRunOfTheWeek()
    {
        Assert.Equal("≈16 min", Stats(Record(words: 400, duration: 120),
                                      Record(daysAgo: 1, words: 400, duration: 120)).TypingSaved);
    }

    [Fact]
    public void ASavingUnderAMinuteSaysSoRatherThanRoundingItAway()
    {
        // 40 words is a minute of typing, and they took most of a minute to say.
        Assert.Equal("<1 min", Stats(Record(words: 40, duration: 36)).TypingSaved);
    }

    [Fact]
    public void SpeakingSlowerThanTypingSavesNothing()
    {
        Assert.Equal("<1 min", Stats(Record(words: 40, duration: 300)).TypingSaved);
    }

    [Fact]
    public void TypingSavedIsUnknownWhenNothingWasTimed()
    {
        Assert.Equal("—", Stats(Record(words: 400)).TypingSaved);
        Assert.Equal("—", Stats().TypingSaved);
    }
}
