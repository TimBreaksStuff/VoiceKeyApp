using VoiceKey.Core;

namespace VoiceKey.App;

internal enum Pane { Transcripts, Dictionary }

/// <summary>
/// Everything the window draws. AppController owns it and pushes a new value
/// whenever something changes; the window redraws what moved.
/// </summary>
/// <param name="ShowsOnboarding">The getting-started strip, until it retires itself.</param>
internal sealed record MainWindowModel(
    TranscriptHistory History,
    DictationStatus Status,
    string Shortcut,
    Grant Microphone,
    Grant Model,
    bool ShowsOnboarding);

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
    void OpenLog();
    void OpenPrivacy(Subject subject);
}
