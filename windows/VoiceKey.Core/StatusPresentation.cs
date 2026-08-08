using System.Globalization;

namespace VoiceKey.Core;

/// <summary>What the app is doing right now. Drives the tray glyph and the menu header.</summary>
public abstract record DictationStatus
{
    private DictationStatus() { }

    public sealed record LoadingState : DictationStatus;
    public sealed record IdleState : DictationStatus;
    public sealed record RecordingState(int Elapsed) : DictationStatus;
    public sealed record TranscribingState : DictationStatus;
    public sealed record ErrorState(string Message) : DictationStatus;

    public static readonly DictationStatus Loading = new LoadingState();
    public static readonly DictationStatus Idle = new IdleState();
    public static readonly DictationStatus Transcribing = new TranscribingState();

    public static DictationStatus Recording(int elapsed) => new RecordingState(elapsed);
    public static DictationStatus Error(string message) => new ErrorState(message);

    /// <summary>
    /// Where to land when nothing is happening. Idle — unless the shortcut never
    /// bound, in which case that is the one thing the user needs to know, and
    /// anything finishing afterwards must not paper over it with "Ready".
    /// </summary>
    public static DictationStatus Settled(bool shortcutIsBound, string shortcut) =>
        shortcutIsBound ? Idle : Error($"{shortcut} is taken by another app");
}

public enum Glyph { Idle, Recording }

/// <summary>
/// Everything the tray needs to render a state: a one-or-two-word title, a dim
/// right-hand meta value, the label of the primary action, and which glyph to
/// show. Pure — the WPF side only draws what this returns.
/// </summary>
public sealed record StatusPresentation(string Title, string Meta, string Action,
                                        Glyph Glyph, bool IsDimmed)
{
    public static StatusPresentation Make(DictationStatus status, string shortcut,
                                          string modelName) => status switch
    {
        DictationStatus.LoadingState =>
            new StatusPresentation("Preparing model", ShortModelName(modelName),
                                   "Start Dictation", Glyph.Idle, true),
        DictationStatus.IdleState =>
            new StatusPresentation("Ready", $"{shortcut} hold",
                                   "Start Dictation", Glyph.Idle, false),
        DictationStatus.RecordingState recording =>
            new StatusPresentation("Recording", ElapsedLabel(recording.Elapsed),
                                   "Stop Dictation", Glyph.Recording, false),
        DictationStatus.TranscribingState =>
            new StatusPresentation("Transcribing", ShortModelName(modelName),
                                   "Stop Dictation", Glyph.Recording, false),
        DictationStatus.ErrorState error =>
            new StatusPresentation(error.Message, "", "Retry", Glyph.Idle, true),
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    /// <summary>
    /// "ggml-small.en" → "small.en". The distributor's prefix is noise in a menu;
    /// a name without one is shown verbatim.
    /// </summary>
    private static string ShortModelName(string name)
    {
        var hyphen = name.IndexOf('-');
        return hyphen < 0 ? name : name[(hyphen + 1)..];
    }

    private static string ElapsedLabel(int seconds)
    {
        var total = Math.Max(0, seconds);
        return string.Create(CultureInfo.InvariantCulture, $"{total / 60}:{total % 60:D2}");
    }
}
