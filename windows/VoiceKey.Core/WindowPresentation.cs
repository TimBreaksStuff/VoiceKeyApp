using System.Globalization;

namespace VoiceKey.Core;

/// <summary>State of one thing the app needs before it can dictate.</summary>
public enum Grant
{
    Granted,
    Denied,
    /// <summary>Never asked, or still in flight.</summary>
    Pending,
    /// <summary>Asked and refused elsewhere, or simply not established.</summary>
    Unknown,
}

public enum Subject { Microphone, Model }

/// <summary>Which palette the engine pill wears — the colour carries the state on its own.</summary>
public enum StatusTone { Ready, Listening, Working, Blocked }

/// <param name="Text">"microphone · granted"</param>
/// <param name="NeedsAttention">True when the line is worth clicking: something is missing.</param>
public sealed record PermissionLine(Subject Subject, string Text, bool NeedsAttention);

/// <param name="IsActionable">True when clicking the pill should lead somewhere — an error.</param>
public sealed record StatusPill(string Label, StatusTone Tone, bool IsActionable);

/// <summary>
/// Everything the main window's header shows about the engine. Pure — the view
/// only draws what this returns.
/// </summary>
/// <param name="DateLine">"Wednesday, 5 August" — the view uppercases it.</param>
public sealed record WindowPresentation(string DateLine, StatusPill Pill,
                                        IReadOnlyList<PermissionLine> Permissions)
{
    /// <summary>How many dictations it takes before the strip has served its purpose.</summary>
    private const int OnboardingDictations = 3;

    public static WindowPresentation Make(DictationStatus status, DateTimeOffset now,
                                          TimeZoneInfo? zone, Grant microphone, Grant model) =>
        new(FormattedDate(now, zone ?? TimeZoneInfo.Local),
            PillFor(status),
            [
                Line(Subject.Microphone, microphone, granted: "granted", missing: "denied"),
                Line(Subject.Model, model, granted: "loaded", missing: "unavailable"),
            ]);

    /// <summary>
    /// Whether the getting-started strip belongs on screen. It retires itself once
    /// the shortcut is plainly in the user's hands, and a dismissal is permanent.
    /// </summary>
    public static bool ShowsOnboarding(bool dismissed, int transcripts) =>
        !dismissed && transcripts < OnboardingDictations;

    private static string FormattedDate(DateTimeOffset now, TimeZoneInfo zone) =>
        TimeZoneInfo.ConvertTime(now, zone).ToString("dddd, d MMMM", CultureInfo.InvariantCulture);

    private static StatusPill PillFor(DictationStatus status) => status switch
    {
        DictationStatus.LoadingState => new StatusPill("Preparing…", StatusTone.Working, false),
        DictationStatus.IdleState => new StatusPill("Ready", StatusTone.Ready, false),
        DictationStatus.RecordingState => new StatusPill("Listening…", StatusTone.Listening, false),
        DictationStatus.TranscribingState =>
            new StatusPill("Transcribing…", StatusTone.Working, false),
        DictationStatus.ErrorState error =>
            new StatusPill(error.Message, StatusTone.Blocked, true),
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    private static PermissionLine Line(Subject subject, Grant grant, string granted, string missing)
    {
        var value = grant switch
        {
            Grant.Granted => granted,
            Grant.Denied => missing,
            Grant.Pending => subject == Subject.Model ? "loading" : "not asked",
            _ => missing,
        };
        return new PermissionLine(subject, $"{Name(subject)} · {value}", grant != Grant.Granted);
    }

    private static string Name(Subject subject) =>
        subject == Subject.Microphone ? "microphone" : "model";
}
