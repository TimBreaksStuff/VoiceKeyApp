using System.Globalization;

namespace VoiceKey.Core;

/// <summary>How the library is ordered — the "Newest first ▾" control in the list header.</summary>
public enum TranscriptSort { Newest, Oldest, Longest }

/// <param name="Words">"12 words" — the row's own word count.</param>
public sealed record TranscriptRow(Guid Id, string Time, string Text, string Words);

/// <param name="Label">"Today", "Yesterday", or the day ("Sun 2 August").</param>
/// <param name="Meta">"14 transcripts · 2,140 words".</param>
public sealed record TranscriptGroup(string Label, string Meta, IReadOnlyList<TranscriptRow> Rows);

/// <summary>
/// The main window's transcript list: the days that have something in them, each
/// with its rows, after the search box and the sort control have had their say.
/// Pure — the view only draws what this returns.
/// </summary>
public sealed class TranscriptList
{
    public IReadOnlyList<TranscriptGroup> Groups { get; }

    /// <summary>True when there is nothing to draw — no history, or nothing matched.</summary>
    public bool IsEmpty => Groups.Count == 0;

    private TranscriptList(IReadOnlyList<TranscriptGroup> groups) => Groups = groups;

    public static TranscriptList Make(IEnumerable<Transcript> records, DateTimeOffset now,
                                      TimeZoneInfo? zone = null, string query = "",
                                      TranscriptSort sort = TranscriptSort.Newest)
    {
        zone ??= TimeZoneInfo.Local;
        var today = DayOf(now, zone);
        var matching = records.Where(record => Matches(record, query));

        var days = matching.GroupBy(record => DayOf(record.Date, zone))
            .OrderBy(group => group.Key, DayOrder(sort));

        return new TranscriptList(days.Select(day =>
        {
            var ofDay = day.Order(RowOrder(sort)).ToArray();
            return new TranscriptGroup(Label(day.Key, today), Meta(ofDay),
                                       ofDay.Select(record => Row(record, zone)).ToArray());
        }).ToArray());
    }

    /// <summary>
    /// The status bar's left half: how much is held, and the reassurance that goes
    /// with it. Fixed copy — the privacy claim is the point of the line.
    /// </summary>
    public static string StorageLine(int count) =>
        $"{Count(count, "transcript")} stored on this machine · nothing is uploaded";

    // MARK: - Filtering and ordering

    private static bool Matches(Transcript record, string query)
    {
        var needle = query.Trim();
        return needle.Length == 0
               || record.Text.Contains(needle, StringComparison.CurrentCultureIgnoreCase);
    }

    private static IComparer<DateTime> DayOrder(TranscriptSort sort) =>
        sort == TranscriptSort.Oldest
            ? Comparer<DateTime>.Default
            : Comparer<DateTime>.Create((left, right) => right.CompareTo(left));

    /// <summary>
    /// Longest-first still falls back to newest-first, so two transcripts of the
    /// same length keep the order the user watched them arrive in.
    /// </summary>
    private static IComparer<Transcript> RowOrder(TranscriptSort sort) => sort switch
    {
        TranscriptSort.Oldest => Comparer<Transcript>.Create(
            (left, right) => left.Date.CompareTo(right.Date)),
        TranscriptSort.Longest => Comparer<Transcript>.Create((left, right) =>
        {
            var byLength = right.WordCount.CompareTo(left.WordCount);
            return byLength != 0 ? byLength : right.Date.CompareTo(left.Date);
        }),
        _ => Comparer<Transcript>.Create((left, right) => right.Date.CompareTo(left.Date)),
    };

    // MARK: - Rendering

    private static DateTime DayOf(DateTimeOffset instant, TimeZoneInfo zone) =>
        TimeZoneInfo.ConvertTime(instant, zone).Date;

    private static TranscriptRow Row(Transcript record, TimeZoneInfo zone) =>
        new(record.Id,
            TimeZoneInfo.ConvertTime(record.Date, zone)
                .ToString("hh:mm tt", CultureInfo.InvariantCulture),
            record.Text,
            Count(record.WordCount, "word"));

    /// <summary>
    /// Fixed English formats: the numerals and month names are part of the
    /// window's design, not something to re-localise per machine.
    /// </summary>
    private static string Label(DateTime day, DateTime today) => (today - day).Days switch
    {
        0 => "Today",
        1 => "Yesterday",
        _ => day.ToString(day.Year == today.Year ? "ddd d MMMM" : "ddd d MMMM yyyy",
                          CultureInfo.InvariantCulture),
    };

    private static string Meta(IReadOnlyCollection<Transcript> records) =>
        $"{Count(records.Count, "transcript")} · " +
        $"{Count(records.Sum(record => record.WordCount), "word")}";

    private static string Count(int amount, string noun) =>
        $"{TranscriptStats.Grouped(amount)} {noun}{(amount == 1 ? "" : "s")}";
}
