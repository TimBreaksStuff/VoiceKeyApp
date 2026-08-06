using System.Globalization;

namespace VoiceKey.Core;

/// <summary>
/// The sidebar's "This week" card, derived from local history alone: what was
/// dictated since Monday, how fast it was spoken, and what that saved.
///
/// Every figure is a finished string — a week with nothing in it still shows a
/// card, with an em dash where there is no honest number to give.
/// </summary>
/// <param name="Words">"1,284" — words dictated this week.</param>
/// <param name="Pace">"127 wpm", or "—" when no run was timed.</param>
/// <param name="TypingSaved">"≈18 min", "&lt;1 min", or "—".</param>
public sealed record TranscriptStats(string Words, string Pace, string TypingSaved)
{
    /// <summary>
    /// The typing speed the saving is measured against — a middling office typist,
    /// deliberately conservative, so the number is never flattering by accident.
    /// </summary>
    private const double TypedWordsPerMinute = 40;

    private const string Unknown = "—";

    public static TranscriptStats Make(IEnumerable<Transcript> records, DateTimeOffset now,
                                       TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        var start = WeekStart(now, zone);
        var thisWeek = records.Where(record => WeekStart(record.Date, zone) == start).ToArray();
        var timed = thisWeek.Where(record => record.Duration > TimeSpan.Zero).ToArray();

        return new TranscriptStats(Grouped(thisWeek.Sum(record => record.WordCount)),
                                   MedianPace(timed),
                                   SavedLabel(timed));
    }

    /// <summary>Weeks start on Monday, so "this week" means the same thing on every machine.</summary>
    private static DateTime WeekStart(DateTimeOffset instant, TimeZoneInfo zone)
    {
        var day = TimeZoneInfo.ConvertTime(instant, zone).Date;
        return day.AddDays(-(((int)day.DayOfWeek + 6) % 7));
    }

    /// <summary>
    /// "2140" → "2,140". Fixed separator: the design's numerals are part of its
    /// look, not something to localise.
    /// </summary>
    public static string Grouped(int count) =>
        count.ToString("#,##0", CultureInfo.InvariantCulture);

    // MARK: - Pace

    /// <summary>The median rather than the mean, so one odd run does not skew it.</summary>
    private static string MedianPace(IReadOnlyList<Transcript> timed)
    {
        var rates = timed.Select(record => record.WordCount / record.Duration.TotalMinutes)
            .Order()
            .ToArray();
        if (rates.Length == 0) return Unknown;

        var middle = rates.Length / 2;
        var median = rates.Length % 2 == 0
            ? (rates[middle - 1] + rates[middle]) / 2
            : rates[middle];
        return $"{(int)Math.Round(median, MidpointRounding.AwayFromZero)} wpm";
    }

    // MARK: - Typing saved

    /// <summary>
    /// How long those words would have taken to type, less the time actually spent
    /// speaking them. Only timed runs count — an untimed one has no speaking time
    /// to subtract, and counting it would inflate the saving.
    /// </summary>
    private static string SavedLabel(IReadOnlyList<Transcript> timed)
    {
        if (timed.Count == 0) return Unknown;

        var typing = timed.Sum(record => record.WordCount) / TypedWordsPerMinute;
        var speaking = timed.Sum(record => record.Duration.TotalMinutes);
        var saved = Math.Round(typing - speaking, MidpointRounding.AwayFromZero);
        return saved < 1 ? "<1 min" : $"≈{Grouped((int)saved)} min";
    }
}
