using System.Diagnostics;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Threading;
using NAudio.CoreAudioApi;
using VoiceKey.Core;
using Application = System.Windows.Application;

namespace VoiceKey.App;

/// <summary>
/// The app: tray icon, state machine, and the transcript pipeline that ties the
/// hotkey, the recorder, whisper and the text inserter together. Everything with
/// testable logic lives in VoiceKey.Core; this class only wires and draws.
/// </summary>
internal sealed class AppController : IDisposable
{
    /// <summary>
    /// A press that starts recording remembers when; a release after this long was
    /// a hold — stop and insert. A quicker tap leaves recording running (toggle mode).
    /// </summary>
    private static readonly TimeSpan HoldThreshold = TimeSpan.FromMilliseconds(350);

    private readonly NotifyIcon _tray = new();
    private readonly AudioRecorder _recorder = new();
    private readonly Transcriber _transcriber = new();
    private readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Dispatcher _dispatcher = Application.Current.Dispatcher;

    private HotKey? _hotKey;
    private Shortcut _shortcut = Shortcut.Default;
    private Preferences _preferences = new();
    private TranscriptHistory _history = new();
    /// <summary>The last transcript deleted from the window, for as long as undo can reach it.</summary>
    private Transcript? _lastDeleted;
    private MainWindow? _window;

    private DictationStatus _status = DictationStatus.Loading;
    private DateTimeOffset? _recordingStartedByPressAt;
    private DateTimeOffset? _recordingStartedAt;

    private Grant _microphoneGrant = Grant.Pending;
    private Grant _modelGrant = Grant.Pending;

    // Menu items whose text or enablement changes with the state.
    private ToolStripMenuItem _headerItem = null!;
    private ToolStripMenuItem _privacyItem = null!;
    private ToolStripMenuItem _toggleItem = null!;
    private ToolStripMenuItem _copyLastItem = null!;
    private ToolStripMenuItem _recentItem = null!;

    internal void Start()
    {
        Storage.Prepare();
        Log.TrimIfLarge();
        Log.Line("launched");

        _history = TranscriptHistory.Load(Storage.History) ?? new TranscriptHistory();
        Log.Line($"history loaded — {_history.Records.Count} transcripts");

        _shortcut = Shortcut.Load();
        _preferences = Preferences.Load();
        BuildTray();
        RegisterHotKey();

        _recorder.OnAutoStop = () => _dispatcher.BeginInvoke(() =>
        {
            if (_status is not DictationStatus.RecordingState) return;
            Log.Line("auto-stop after trailing silence");
            FinishRecording();
        });

        _tick.Tick += (_, _) => SyncUi();
        _microphoneGrant = HasCaptureDevice() ? Grant.Granted : Grant.Denied;
        Log.Line($"microphone device present={_microphoneGrant == Grant.Granted}");

        SyncUi();
        ShowWindow();
        _ = LoadModelAsync();
    }

    private async Task LoadModelAsync()
    {
        try
        {
            await _transcriber.LoadAsync();
            _modelGrant = Grant.Granted;
            SetStatus(Settled);
        }
        catch (Exception exception)
        {
            Log.Line($"model load FAILED: {exception}");
            _modelGrant = Grant.Denied;
            SetStatus(DictationStatus.Error($"Model load failed: {exception.Message}"));
        }
    }

    /// <summary>
    /// Windows has no permission prompt for a desktop app's microphone — the
    /// grant is a Settings toggle — so the closest thing to a check is whether a
    /// capture device can be seen at all.
    /// </summary>
    private static bool HasCaptureDevice()
    {
        try
        {
            using var devices = new MMDeviceEnumerator();
            return devices.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).Count > 0;
        }
        catch (Exception exception)
        {
            Log.Line($"could not enumerate capture devices: {exception.Message}");
            return false;
        }
    }

    // MARK: - Tray

    private void BuildTray()
    {
        var menu = new ContextMenuStrip { ShowImageMargin = false };

        _headerItem = new ToolStripMenuItem("") { Enabled = false };
        menu.Items.Add(_headerItem);

        // Only shown in the error state, where it is the actionable item.
        _privacyItem = Item("Open Sound Settings…", OpenPrivacySettings);
        _privacyItem.Visible = false;
        menu.Items.Add(_privacyItem);

        _toggleItem = Item("Start Dictation", (_, _) => HotKeyPressed());
        menu.Items.Add(_toggleItem);
        _copyLastItem = Item("Copy Last Transcript", (_, _) => CopyLastTranscript());
        menu.Items.Add(_copyLastItem);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(SectionHeader("Transcripts"));
        _recentItem = new ToolStripMenuItem("Recent");
        menu.Items.Add(_recentItem);
        menu.Items.Add(Item("All Transcripts…", (_, _) => ShowWindow(Pane.Transcripts)));
        menu.Items.Add(Item("Dictionary…", (_, _) => ShowWindow(Pane.Dictionary)));

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(SectionHeader("Setup"));
        menu.Items.Add(Item("Shortcut…", (_, _) => ChangeShortcut()));
        menu.Items.Add(Item("Diagnostics Log", (_, _) => OpenLog()));

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item("Quit VoiceKey", (_, _) => Application.Current.Shutdown()));

        RebuildRecentMenu();

        _tray.ContextMenuStrip = menu;
        _tray.Visible = true;
        // Windows convention, unlike the Mac build: left click opens the window,
        // right click opens the menu (which NotifyIcon does on its own).
        _tray.MouseClick += (_, args) =>
        {
            if (args.Button == MouseButtons.Left) ShowWindow();
        };
    }

    private static ToolStripMenuItem Item(string title, EventHandler onClick)
    {
        var item = new ToolStripMenuItem(title);
        item.Click += onClick;
        return item;
    }

    private static ToolStripLabel SectionHeader(string title) =>
        new(title)
        {
            Enabled = false,
            Font = new System.Drawing.Font(System.Drawing.SystemFonts.MenuFont!,
                                           System.Drawing.FontStyle.Bold),
        };

    private void RebuildRecentMenu()
    {
        _recentItem.DropDownItems.Clear();
        if (_history.Entries.Count == 0)
        {
            _recentItem.DropDownItems.Add(new ToolStripMenuItem("No transcripts yet") { Enabled = false });
            return;
        }
        foreach (var entry in _history.Entries)
        {
            var item = Item(TranscriptHistory.MenuTitle(entry), (_, _) => Copy(entry));
            item.ToolTipText = entry;
            _recentItem.DropDownItems.Add(item);
        }
        _recentItem.DropDownItems.Add(new ToolStripSeparator());
        _recentItem.DropDownItems.Add(Item("Clear History", (_, _) => ClearHistory()));
    }

    // MARK: - State

    private void SetStatus(DictationStatus status)
    {
        _status = status;
        SyncTimer();
        SyncUi();
    }

    /// <summary>Recomputes the elapsed seconds, which tick while recording.</summary>
    private DictationStatus CurrentStatus => _status is DictationStatus.RecordingState
        ? DictationStatus.Recording(
            (int)(DateTimeOffset.Now - (_recordingStartedAt ?? DateTimeOffset.Now)).TotalSeconds)
        : _status;

    private void SyncUi()
    {
        var status = CurrentStatus;
        var presentation = StatusPresentation.Make(status, _shortcut.Label, Transcriber.ModelName);

        _tray.Icon = TrayGlyph.For(presentation.Glyph, presentation.IsDimmed);
        _tray.Text = Truncated($"VoiceKey — {presentation.Title}");
        _headerItem.Text = presentation.Meta.Length == 0
            ? presentation.Title
            : $"{presentation.Title}     {presentation.Meta}";
        _toggleItem.Text = presentation.Action;
        _copyLastItem.Enabled = _history.Entries.Count > 0;
        _privacyItem.Visible = status is DictationStatus.ErrorState;

        _window?.Apply(new MainWindowModel(
            _history, status, _shortcut.Label, _microphoneGrant, _modelGrant,
            WindowPresentation.ShowsOnboarding(_preferences.OnboardingDismissed,
                                               _history.Records.Count),
            LoginItem.Read()));
    }

    /// <summary>A NotifyIcon tooltip is capped at 63 characters; longer text is dropped silently.</summary>
    private static string Truncated(string text) => text.Length <= 63 ? text : text[..63];

    private void SyncTimer()
    {
        if (_status is DictationStatus.RecordingState)
        {
            if (_tick.IsEnabled) return;
            _recordingStartedAt = DateTimeOffset.Now;
            _tick.Start();
        }
        else
        {
            _tick.Stop();
            _recordingStartedAt = null;
        }
    }

    // MARK: - Hotkey

    private void RegisterHotKey()
    {
        _hotKey?.Dispose();
        _hotKey = new HotKey(_shortcut, HotKeyPressed, HotKeyReleased);
        Log.Line($"hotkey bound to {_shortcut.Label} (registered={ShortcutIsBound})");
        if (!ShortcutIsBound) SetStatus(Settled);
    }

    private bool ShortcutIsBound => _hotKey is { IsRegistered: true };

    /// <summary>
    /// The state to be in when nothing is happening. Going through this rather
    /// than straight to Idle is what stops a finished model load, or a discarded
    /// recording, from reporting "Ready" over a shortcut that never bound.
    /// </summary>
    private DictationStatus Settled => DictationStatus.Settled(ShortcutIsBound, _shortcut.Label);

    private void HotKeyPressed()
    {
        Log.Line($"hotkey press (state={_status.GetType().Name})");
        switch (_status)
        {
            case DictationStatus.IdleState:
                try
                {
                    _recorder.Start();
                    _recordingStartedByPressAt = DateTimeOffset.Now;
                    _microphoneGrant = Grant.Granted;
                    SetStatus(DictationStatus.Recording(0));
                }
                catch (Exception exception)
                {
                    Log.Line($"recorder start FAILED: {exception}");
                    _microphoneGrant = Grant.Denied;
                    SetStatus(DictationStatus.Error("Mic not ready — check microphone access"));
                }
                break;
            case DictationStatus.RecordingState:
                _recordingStartedByPressAt = null; // a toggle-stop; ignore its release
                FinishRecording();
                break;
            case DictationStatus.ErrorState:
                // "Retry" from the menu: rebind the shortcut if that is what
                // failed, then report wherever that leaves us.
                if (!ShortcutIsBound) RegisterHotKey();
                else SetStatus(Settled);
                break;
        }
    }

    private void HotKeyReleased()
    {
        if (_status is not DictationStatus.RecordingState || _recordingStartedByPressAt is null) return;
        var held = DateTimeOffset.Now - _recordingStartedByPressAt.Value;
        Log.Line(string.Create(System.Globalization.CultureInfo.InvariantCulture,
            $"hotkey release after {held.TotalSeconds:F2}s"));
        if (held < HoldThreshold) return; // quick tap → stay in toggle mode
        FinishRecording();
    }

    // MARK: - Dictation

    private void FinishRecording()
    {
        _recordingStartedByPressAt = null;
        SetStatus(DictationStatus.Transcribing);

        var (samples, heardSpeech) = _recorder.Stop();
        var duration = TimeSpan.FromSeconds(samples.Length / 16_000.0); // recorder resamples to 16 kHz
        Log.Line(string.Create(System.Globalization.CultureInfo.InvariantCulture,
            $"stopped — {samples.Length} samples ({duration.TotalSeconds:F1}s), heardSpeech={heardSpeech}"));
        if (!heardSpeech)
        {
            SetStatus(Settled);
            return;
        }

        // Reload each time so edits to dictionary.json apply without a restart.
        // Missing or broken file → empty dictionary, NOT the template: template
        // rules must never rewrite words the user did not opt into.
        var dictionary = VocabularyDictionary.Load(Storage.Dictionary) ?? new VocabularyDictionary();
        _ = TranscribeAsync(samples, duration, dictionary);
    }

    private async Task TranscribeAsync(float[] samples, TimeSpan duration,
                                       VocabularyDictionary dictionary)
    {
        try
        {
            var raw = await _transcriber.TranscribeAsync(samples, dictionary.PromptText);
            Log.Line($"transcript: \"{raw}\"");

            var process = ForegroundApp.ProcessName();
            var text = Polish(raw, dictionary, process);
            Log.Line($"polished for {process ?? "unknown app"}: \"{text}\"");
            if (text.Length == 0)
            {
                SetStatus(Settled);
                return;
            }

            Deliver(text, process);
            Record(text, duration);
            SetStatus(Settled);
        }
        catch (Exception exception)
        {
            Log.Line($"transcription FAILED: {exception}");
            SetStatus(DictationStatus.Error($"Transcription failed: {exception.Message}"));
        }
    }

    /// <summary>
    /// Raw whisper output → pasteable text: drop non-speech annotations, strip
    /// fillers and stutters, apply the user's replacement rules, then format for
    /// the app the text lands in. Pure — all logic lives in VoiceKey.Core.
    /// </summary>
    private static string Polish(string raw, VocabularyDictionary dictionary, string? process)
    {
        if (TranscriptCleaner.IsNonSpeechAnnotation(raw)) return "";
        var cleaned = TranscriptCleaner.Clean(raw);
        var replaced = dictionary.ApplyingReplacements(cleaned);
        return DictationModes.ForProcess(process).Format(replaced);
    }

    /// <summary>
    /// Types the transcript at the cursor — unless that cursor is in VoiceKey's
    /// own window, where pasting would land in the search field and filter the
    /// library down to the transcript just spoken. The clipboard takes it instead.
    /// </summary>
    private static void Deliver(string text, string? frontmostProcess)
    {
        if (DictationModes.InsertsAtCursor(frontmostProcess, OwnProcessName))
        {
            TextInserter.Insert(text);
            return;
        }
        Log.Line("VoiceKey is frontmost — copied instead of pasting into our own window");
        Copy(text);
    }

    private static string OwnProcessName { get; } = Process.GetCurrentProcess().ProcessName;

    private static void Copy(string text)
    {
        try
        {
            System.Windows.Clipboard.SetText(text);
        }
        catch (Exception exception)
        {
            Log.Line($"clipboard copy FAILED: {exception.Message}");
        }
    }

    private void CopyLastTranscript()
    {
        if (_history.Entries.FirstOrDefault() is { } latest) Copy(latest);
    }

    // MARK: - History

    private void Record(string text, TimeSpan duration)
    {
        _history = _history.Adding(text, DateTimeOffset.Now, duration);
        PersistHistory();
        RebuildRecentMenu();
    }

    private void ClearHistory()
    {
        _history = _history.Cleared();
        PersistHistory();
        RebuildRecentMenu();
        SyncUi();
    }

    private void PersistHistory()
    {
        try
        {
            _history.Save(Storage.History);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Log.Line($"history save FAILED: {exception.Message}");
        }
    }

    // MARK: - Menu actions

    private void ChangeShortcut()
    {
        var captured = ShortcutWindow.Capture(_window);
        if (captured is null) return;

        // Rebinding can only fix one error — the old shortcut being taken. Any
        // other error (a model that would not load) has to survive this.
        var wasBlockedByTheShortcut = _status == Settled;
        _shortcut = captured;
        _shortcut.Save();
        RegisterHotKey();
        if (wasBlockedByTheShortcut && ShortcutIsBound) SetStatus(Settled);
        SyncUi();
    }

    private static void OpenLog() => Open(Storage.LogFile);

    /// <summary>
    /// Windows grants no accessibility permission — SendInput needs none — so the
    /// only thing worth opening is the microphone privacy page.
    /// </summary>
    private static void OpenPrivacySettings(object? sender, EventArgs args) =>
        Open("ms-settings:privacy-microphone");

    private static void Open(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            Log.Line($"could not open {target}: {exception.Message}");
        }
    }

    // MARK: - Window

    private void ShowWindow(Pane pane = Pane.Transcripts)
    {
        if (_window is null)
        {
            _window = new MainWindow(new WindowActions(this));
            _window.Closed += (_, _) => _window = null;
        }
        SyncUi();
        _window.Show(pane);
    }

    /// <summary>What the window is allowed to ask the app to do.</summary>
    private sealed class WindowActions(AppController controller) : IMainWindowActions
    {
        public void Copy(string text) => AppController.Copy(text);

        public void AddTerm(string text) =>
            controller._window?.AddDictionaryTerm(VocabularyDictionary.SuggestedTerm(text));

        public void Delete(Guid id)
        {
            controller._lastDeleted = controller._history.Records
                .FirstOrDefault(record => record.Id == id);
            controller._history = controller._history.Removing(id);
            controller.PersistHistory();
            controller.RebuildRecentMenu();
            controller.SyncUi();
        }

        public void UndoDelete()
        {
            if (controller._lastDeleted is not { } record) return;
            controller._lastDeleted = null;
            controller._history = controller._history.Restoring(record);
            controller.PersistHistory();
            controller.RebuildRecentMenu();
            controller.SyncUi();
        }

        public void DeleteAll() => controller.ClearHistory();

        /// <summary>
        /// The whole log as one plain-text file, wherever the user points. Export
        /// is a copy — nothing is removed and nothing leaves the machine on its own.
        /// </summary>
        public void ExportAll()
        {
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Title = "Export transcripts",
                FileName = $"VoiceKey transcripts {DateTime.Now:yyyy-MM-dd}.txt",
                Filter = "Text file (*.txt)|*.txt",
                DefaultExt = ".txt",
            };
            if (dialog.ShowDialog(controller._window) != true) return;

            try
            {
                File.WriteAllText(dialog.FileName, controller._history.ExportText());
                Log.Line($"exported {controller._history.Records.Count} transcripts");
            }
            catch (Exception exception) when (exception is IOException
                or UnauthorizedAccessException)
            {
                Log.Line($"export FAILED: {exception.Message}");
                System.Windows.MessageBox.Show($"Could not write the file: {exception.Message}",
                    "Export transcripts", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        public void DismissOnboarding()
        {
            controller._preferences = controller._preferences with { OnboardingDismissed = true };
            controller._preferences.Save();
        }

        public void ChangeShortcut() => controller.ChangeShortcut();

        /// <summary>
        /// Acts on what the system reports right now, not on what the row was
        /// last drawn with — the switch can also be flipped in Task Manager.
        /// </summary>
        public void ToggleLaunchAtLogin()
        {
            switch (LaunchAtLogin.Click(LoginItem.Read()))
            {
                case LaunchAtLoginAction.Enable: LoginItem.Set(true); break;
                case LaunchAtLoginAction.Disable: LoginItem.Set(false); break;
                case LaunchAtLoginAction.OpenSettings: Open("ms-settings:startupapps"); break;
            }
            controller.SyncUi();
        }

        public void OpenLog() => AppController.OpenLog();

        public void OpenPrivacy(Subject subject)
        {
            if (subject == Subject.Microphone) Open("ms-settings:privacy-microphone");
        }
    }

    public void Dispose()
    {
        _tick.Stop();
        _hotKey?.Dispose();
        _recorder.Dispose();
        _transcriber.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
    }
}
