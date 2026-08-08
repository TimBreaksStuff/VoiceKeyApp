using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// The app's one window: a fixed sidebar and header over a scrolling pane.
/// Everything it shows is computed by VoiceKey.Core — this class only draws.
/// </summary>
public partial class MainWindow : Window
{
    private readonly IMainWindowActions _actions;
    private readonly TranscriptsPane _transcriptsPane;
    private readonly DictionaryPane _dictionaryPane;
    private MainWindowModel? _model;

    internal MainWindow(IMainWindowActions actions)
    {
        _actions = actions;
        InitializeComponent();
        _transcriptsPane = new TranscriptsPane(actions, ShowHelp);
        _dictionaryPane = new DictionaryPane(RefreshDictionaryCount);
        Select(Pane.Transcripts);
        SizeChanged += (_, args) => _transcriptsPane.SetWidth(args.NewSize.Width);
        PreviewKeyDown += OnPreviewKeyDown;
    }

    internal void Show(Pane pane)
    {
        // After the handle exists, so it replaces the icon WPF takes from the
        // executable — and on every open, since either theme can have been
        // switched since the last one.
        TrayGlyph.ApplyWindowIcons(new WindowInteropHelper(this).EnsureHandle());
        Select(pane);
        if (!IsVisible) base.Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    /// <summary>
    /// Redraws whatever the new model changed. The transcript list is rebuilt only
    /// when it actually differs — the recording clock updates the status every
    /// second and must not throw the list away underneath the user.
    /// </summary>
    internal void Apply(MainWindowModel model)
    {
        var previous = _model;
        _model = model;

        var presentation = WindowPresentation.Make(model.Status, DateTimeOffset.Now,
                                                   TimeZoneInfo.Local,
                                                   model.Microphone, model.Model);

        DateLabel.Text = presentation.DateLine.ToUpperInvariant();
        ApplyLaunchAtLogin(model.LaunchAtLogin);
        SoundCuesLink.Content = CueSound.Label(model.SoundCues);
        ApplyStopOnSilence(model.StopOnSilence);
        ApplyUpdate(model.Update);
        ApplyPill(presentation.Pill);
        RebuildPermissions(presentation.Permissions);
        ApplyStats(TranscriptStats.Make(model.History.Records, DateTimeOffset.Now));
        NavTranscriptsCount.Text = TranscriptStats.Grouped(model.History.Records.Count);
        RefreshDictionaryCount();

        _transcriptsPane.Apply(model,
            rebuildList: previous is null
                         || !previous.History.Equals(model.History)
                         || previous.Shortcut != model.Shortcut);
    }

    internal void AddDictionaryTerm(string? suggestion)
    {
        Select(Pane.Dictionary);
        _dictionaryPane.AddTerm(suggestion);
    }

    // MARK: - The engine pill

    private void ApplyPill(StatusPill pill)
    {
        var (background, border, dot, ink) = Palette(pill.Tone);
        StatusPillShell.Background = Resource<Brush>(background);
        StatusPillShell.BorderBrush = Resource<Brush>(border);
        StatusDot.Fill = Resource<Brush>(dot);
        StatusLabel.Foreground = Resource<Brush>(ink);
        StatusLabel.Text = pill.Label;
        StatusPillShell.ToolTip = pill.IsActionable
            ? "Open Windows microphone settings"
            : null;
        Pulse(pill.Tone == StatusTone.Listening);
    }

    private static (string Background, string Border, string Dot, string Ink) Palette(
        StatusTone tone) => tone switch
    {
        StatusTone.Ready => ("GreenBg", "GreenBorder", "Green", "GreenInk"),
        StatusTone.Working => ("WorkingBg", "WorkingBorder", "Muted2", "Ink3"),
        // An error wears the listening palette: the same warmth, a different word.
        _ => ("ClayBg", "ClayBorder", "Clay", "ClayHover"),
    };

    /// <summary>The dot breathes while the microphone is open, and only then.</summary>
    private void Pulse(bool on)
    {
        if (!on)
        {
            StatusDot.BeginAnimation(OpacityProperty, null);
            StatusDotScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
            StatusDotScale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
            StatusDot.Opacity = 1;
            StatusDotScale.ScaleX = StatusDotScale.ScaleY = 1;
            return;
        }
        if (StatusDot.Opacity < 1) return; // already breathing

        var beat = TimeSpan.FromMilliseconds(700);
        DoubleAnimation Breath(double to) => new(to, new Duration(beat))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
        };
        StatusDot.BeginAnimation(OpacityProperty, Breath(0.45));
        StatusDotScale.BeginAnimation(ScaleTransform.ScaleXProperty, Breath(0.86));
        StatusDotScale.BeginAnimation(ScaleTransform.ScaleYProperty, Breath(0.86));
    }

    private void RebuildPermissions(IReadOnlyList<PermissionLine> lines)
    {
        PermissionLines.Children.Clear();
        foreach (var line in lines)
        {
            var label = new TextBlock
            {
                Text = line.Text,
                FontFamily = Resource<FontFamily>("Mono"),
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 6),
                Foreground = Resource<Brush>(line.NeedsAttention ? "Clay" : "Muted3"),
                Cursor = line.NeedsAttention ? Cursors.Hand : null,
            };
            if (line.NeedsAttention)
            {
                var subject = line.Subject;
                label.MouseLeftButtonUp += (_, _) =>
                {
                    PermissionPopup.IsOpen = false;
                    _actions.OpenPrivacy(subject);
                };
            }
            PermissionLines.Children.Add(label);
        }
    }

    private void OnStatusPillClicked(object sender, RoutedEventArgs e) =>
        PermissionPopup.IsOpen = !PermissionPopup.IsOpen;

    // MARK: - This week

    private void ApplyStats(TranscriptStats stats)
    {
        WeekWords.Text = stats.Words;
        WeekPace.Text = stats.Pace;
        WeekSaved.Text = stats.TypingSaved;
    }

    /// <summary>
    /// How much the user has taught VoiceKey: terms plus replacement rules. Read
    /// from the file, which is also where the Dictionary pane edits it.
    /// </summary>
    private void RefreshDictionaryCount()
    {
        // The pane shows the template when there is no file yet, so the count has
        // to fall back to the same thing or it reads 0 over a full table.
        var dictionary = VocabularyDictionary.Load(Storage.Dictionary)
                         ?? VocabularyDictionary.Template;
        NavDictionaryCount.Text = TranscriptStats.Grouped(
            dictionary.Terms.Count + dictionary.Replacements.Count);
    }

    // MARK: - Panes

    private void Select(Pane pane)
    {
        PaneTitle.Text = pane == Pane.Transcripts ? "Transcripts" : "Dictionary";
        SearchShell.Visibility = pane == Pane.Transcripts
            ? Visibility.Visible
            : Visibility.Collapsed;

        Highlight(NavTranscripts, NavTranscriptsLabel, NavTranscriptsCount,
                  active: pane == Pane.Transcripts);
        Highlight(NavDictionary, NavDictionaryLabel, NavDictionaryCount,
                  active: pane == Pane.Dictionary);

        PaneHost.Content = pane == Pane.Transcripts ? _transcriptsPane : _dictionaryPane;
        if (pane == Pane.Dictionary) _dictionaryPane.Reload();
    }

    private static void Highlight(Border shell, TextBlock label, TextBlock count, bool active)
    {
        if (active)
        {
            shell.Background = Resource<Brush>("Paper");
            shell.BorderBrush = Resource<Brush>("Border");
        }
        else
        {
            shell.ClearValue(BackgroundProperty);
            shell.ClearValue(Border.BorderBrushProperty);
        }
        label.FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal;
        label.Foreground = Resource<Brush>(active ? "Ink" : "Ink3");
        count.Foreground = Resource<Brush>(active ? "Muted2" : "Muted3");
    }

    private void OnTranscriptsClicked(object sender, RoutedEventArgs e) => Select(Pane.Transcripts);

    private void OnDictionaryClicked(object sender, RoutedEventArgs e) => Select(Pane.Dictionary);

    private void OnShortcutClicked(object sender, RoutedEventArgs e)
    {
        SettingsPopup.IsOpen = false;
        _actions.ChangeShortcut();
    }

    // MARK: - Start with Windows

    /// <summary>
    /// The footer row carries the state the system reports, not a preference of
    /// our own — so a switch flipped in Task Manager shows up here on the next
    /// redraw rather than at the next restart.
    /// </summary>
    private void ApplyLaunchAtLogin(LaunchAtLoginState state)
    {
        LaunchAtLoginLink.Content = LaunchAtLogin.Label("Start with Windows", state);
        LaunchAtLoginLink.ToolTip = state == LaunchAtLoginState.Blocked
            ? "Switched off under Settings › Apps › Startup. Click to open it."
            : null;
    }

    private void OnLaunchAtLoginClicked(object sender, RoutedEventArgs e) =>
        _actions.ToggleLaunchAtLogin();

    private void OnSoundCuesClicked(object sender, RoutedEventArgs e) => _actions.ToggleSoundCues();

    /// <summary>
    /// Off is the mode with a consequence — nothing ends the recording but the
    /// shortcut — so the row says what that means rather than leaving it to be
    /// discovered mid-dictation.
    /// </summary>
    private void ApplyStopOnSilence(bool stopOnSilence)
    {
        StopOnSilenceLink.Content = RecordingStop.Label(stopOnSilence);
        StopOnSilenceLink.ToolTip = stopOnSilence
            ? "A second of quiet ends the recording."
            : "Recording runs until you press the shortcut again (five minutes at most).";
    }

    private void OnStopOnSilenceClicked(object sender, RoutedEventArgs e) =>
        _actions.ToggleStopOnSilence();

    // MARK: - Settings

    /// <summary>
    /// The card grows upwards from its row, which sits at the bottom of the
    /// window — the same trick the help popover uses, and for the same reason.
    /// </summary>
    private void OnSettingsClicked(object sender, RoutedEventArgs e)
    {
        VersionLine.Text = $"VoiceKey {Updater.CurrentVersion}";
        SettingsPopup.PlacementTarget = SettingsLink;
        SettingsPopup.Placement = PlacementMode.Right;
        SettingsPopup.VerticalOffset = 0;
        SettingsPopup.IsOpen = true;
        Dispatcher.BeginInvoke(
            () => SettingsPopup.VerticalOffset = SettingsLink.ActualHeight - SettingsCard.ActualHeight,
            DispatcherPriority.Loaded);
    }

    // MARK: - Updates

    /// <summary>
    /// The same words in two places: a row inside Settings that is always there,
    /// and a footer notice that only appears once there is something to say.
    /// </summary>
    private void ApplyUpdate(UpdateStatus status)
    {
        UpdateLink.Content = AppUpdate.Label(status);
        UpdateNotice.Content = AppUpdate.Label(status);
        UpdateNotice.Visibility = AppUpdate.IsVisible(status)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void OnUpdateClicked(object sender, RoutedEventArgs e) => _actions.ClickUpdate();

    private void OnLogClicked(object sender, RoutedEventArgs e)
    {
        SettingsPopup.IsOpen = false;
        _actions.OpenLog();
    }

    // MARK: - Help

    /// <summary>
    /// The walkthrough, beside whatever asked for it: to the right of the sidebar
    /// link, under a button in the pane.
    /// </summary>
    internal void ShowHelp(FrameworkElement anchor, PlacementMode placement)
    {
        HelpHoldStep.Text =
            $"2. Hold {_model?.Shortcut ?? "the shortcut"} and speak. Release when you are done; " +
            "a quick tap instead keeps recording until you tap again.";
        HelpPopup.PlacementTarget = anchor;
        HelpPopup.Placement = placement;
        HelpPopup.VerticalOffset = 0;
        HelpPopup.IsOpen = true;

        // The sidebar link it hangs off sits at the bottom of the window, so the
        // card has to grow upwards from it rather than off the screen. Its height
        // is only known once the popup has laid itself out.
        if (placement != PlacementMode.Right) return;
        Dispatcher.BeginInvoke(
            () => HelpPopup.VerticalOffset = anchor.ActualHeight - HelpCard.ActualHeight,
            DispatcherPriority.Loaded);
    }

    /// <summary>Help hangs off the Settings row, since that is where its link now lives.</summary>
    private void OnHelpClicked(object sender, RoutedEventArgs e)
    {
        SettingsPopup.IsOpen = false;
        ShowHelp(SettingsLink, PlacementMode.Right);
    }

    private void OnHelpShortcutClicked(object sender, RoutedEventArgs e)
    {
        HelpPopup.IsOpen = false;
        _actions.ChangeShortcut();
    }

    // MARK: - Search

    private void OnSearchChanged(object sender, TextChangedEventArgs e)
    {
        SearchPlaceholder.Visibility = SearchBox.Text.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        _transcriptsPane.SetQuery(SearchBox.Text);
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control)
        {
            Select(Pane.Transcripts);
            SearchBox.Focus();
            SearchBox.SelectAll();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape && SearchBox.Text.Length > 0)
        {
            SearchBox.Clear();
            e.Handled = true;
        }
    }

    // MARK: - Resources

    private static T Resource<T>(string key) => (T)Application.Current.Resources[key];
}
