using VoiceKey.Core;

namespace VoiceKey.App;

internal enum Pane { Transcripts, Dictionary }

/// <summary>
/// Everything the window draws. AppController owns it and pushes a new value
/// whenever something changes; the window redraws what moved.
/// </summary>
/// <param name="ShowsOnboarding">The getting-started strip, until it retires itself.</param>
/// <param name="LaunchAtLogin">What the system reports about starting with Windows.</param>
/// <param name="SoundCues">Whether starting and stopping a dictation plays its cue.</param>
/// <param name="Update">How far the check for a newer VoiceKey has got.</param>
internal sealed record MainWindowModel(
    TranscriptHistory History,
    DictationStatus Status,
    string Shortcut,
    Grant Microphone,
    Grant Model,
    bool ShowsOnboarding,
    LaunchAtLoginState LaunchAtLogin,
    bool SoundCues,
    UpdateStatus Update);

/// <summary>
/// What the window asks the app to do. Keeps WPF out of the state machine and
/// the state machine out of the views.
/// </summary>
internal interface IMainWindowActions
{
    void Copy(string text);
    void AddTerm(string text);
    void Delete(Guid id);
    /// <summary>Puts the last deleted transcript back — what the undo toast calls.</summary>
    void UndoDelete();
    void DeleteAll();
    void ExportAll();
    void DismissOnboarding();
    void ChangeShortcut();
    void ToggleLaunchAtLogin();
    void ToggleSoundCues();
    /// <summary>Check, install, or nothing — whichever the row's state calls for.</summary>
    void ClickUpdate();
    void OpenLog();
    void OpenPrivacy(Subject subject);
}
