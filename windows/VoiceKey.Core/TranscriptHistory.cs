using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoiceKey.Core;

/// <summary>
/// One dictation: what was typed, when, and how long the recording ran.
///
/// The duration is what makes a words-per-minute figure possible; it is zero when
/// a transcript arrives from somewhere that did not time the recording.
/// </summary>
public sealed record Transcript(Guid Id, string Text, DateTimeOffset Date, TimeSpan Duration)
{
    public Transcript(string text, DateTimeOffset date, TimeSpan duration = default)
        : this(Guid.NewGuid(), text, date, duration) { }

    public int WordCount => Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
}

/// <summary>
/// The dictation log, newest first: the tray menu lists the newest few, the
/// main window shows all of them grouped by day, and the stats derive from it.
///
/// Persisted to <c>history.json</c> next to the dictionary — the window's list and
/// its lifetime stats have to survive a relaunch to mean anything.
/// </summary>
public sealed class TranscriptHistory : IEquatable<TranscriptHistory>
{
    /// <summary>How many transcripts the tray menu lists.</summary>
    private const int MenuLimit = 10;
    /// <summary>Ceiling on what is kept, so the file cannot grow without bound.</summary>
    private const int StorageLimit = 2_000;

    /// <summary>Every recorded dictation, newest first.</summary>
    public IReadOnlyList<Transcript> Records { get; }

    public TranscriptHistory() => Records = [];

    public TranscriptHistory(IEnumerable<Transcript> records) =>
        Records = records.Take(StorageLimit).ToArray();

    /// <summary>The newest transcripts' text, newest first — what the tray menu lists.</summary>
    public IReadOnlyList<string> Entries =>
        Records.Take(MenuLimit).Select(record => record.Text).ToArray();

    /// <summary>
    /// Returns a new history with <paramref name="transcript"/> prepended.
    ///
    /// Blank transcripts and an immediate repeat of the newest entry are ignored,
    /// and the oldest record is dropped once the storage limit is reached.
    /// </summary>
    public TranscriptHistory Adding(string transcript, DateTimeOffset? at = null,
                                    TimeSpan duration = default)
    {
        if (string.IsNullOrWhiteSpace(transcript)) return this;
        if (Records.Count > 0 && Records[0].Text == transcript) return this;
        var record = new Transcript(transcript, at ?? DateTimeOffset.Now, duration);
        return new TranscriptHistory(Records.Prepend(record));
    }

    /// <summary>Returns a new history without the given record; unknown ids change nothing.</summary>
    public TranscriptHistory Removing(Guid id) =>
        new(Records.Where(record => record.Id != id));

    /// <summary>
    /// Returns a new history with the record put back in date order — what the
    /// undo after a delete calls. A record that is already there changes nothing.
    /// </summary>
    public TranscriptHistory Restoring(Transcript record) =>
        Records.Any(existing => existing.Id == record.Id)
            ? this
            : new TranscriptHistory(Records.Append(record).OrderByDescending(entry => entry.Date));

    /// <summary>Returns an empty history — every transcript deleted at once.</summary>
    public TranscriptHistory Cleared() => new();

    /// <summary>
    /// The whole log as plain text, newest first, each transcript under its own
    /// timestamp — what "Export all" writes.
    /// </summary>
    public string ExportText(TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        return string.Join("\n", Records.Select(record =>
            TimeZoneInfo.ConvertTime(record.Date, zone)
                .ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture)
            + "\n" + record.Text + "\n"));
    }

    /// <summary>True when there is nothing recorded, and so nothing to clear.</summary>
    public bool IsEmpty => Records.Count == 0;

    /// <summary>
    /// Display-only, single-line rendering of a transcript for a menu item:
    /// whitespace runs collapse to single spaces and anything beyond 60
    /// characters is replaced by an ellipsis.
    /// </summary>
    public static string MenuTitle(string transcript)
    {
        var collapsed = string.Join(" ",
            transcript.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return collapsed.Length <= 60 ? collapsed : collapsed[..60] + "…";
    }

    // MARK: - Storage

    /// <summary>
    /// Reads the log from disk; null when the file is missing or malformed — a
    /// broken file must degrade to "no history", never crash the app.
    /// </summary>
    public static TranscriptHistory? Load(string path)
    {
        try
        {
            var records = JsonSerializer.Deserialize<List<Dto>>(File.ReadAllText(path));
            return records is null
                ? null
                : new TranscriptHistory(records.Select(record => record.ToTranscript()));
        }
        catch (Exception exception) when (exception is IOException or JsonException
            or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(string path) =>
        File.WriteAllText(path,
            JsonSerializer.Serialize(Records.Select(Dto.From), SerializerOptions));

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>
    /// The on-disk shape: seconds rather than a <see cref="TimeSpan"/>, so the file
    /// stays readable and matches what the macOS build writes.
    /// </summary>
    private sealed record Dto(
        [property: JsonPropertyName("id")] Guid Id,
        [property: JsonPropertyName("text")] string Text,
        [property: JsonPropertyName("date")] DateTimeOffset Date,
        [property: JsonPropertyName("duration")] double Duration)
    {
        internal static Dto From(Transcript record) =>
            new(record.Id, record.Text, record.Date, record.Duration.TotalSeconds);

        internal Transcript ToTranscript() =>
            new(Id, Text, Date, TimeSpan.FromSeconds(Duration));
    }

    // MARK: - Equality

    public bool Equals(TranscriptHistory? other) =>
        other is not null && Records.SequenceEqual(other.Records);

    public override bool Equals(object? obj) => Equals(obj as TranscriptHistory);

    public override int GetHashCode() => Records.Count;
}
