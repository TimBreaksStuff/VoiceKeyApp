using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// The library: an optional getting-started strip, the scrolling transcript list
/// — days newest first, every row carrying its own Copy / Insert / ⋯ actions —
/// and the status bar that says what is stored and where.
/// </summary>
public partial class TranscriptsPane : UserControl
{
    /// <summary>How long a row's "Copied" confirmation replaces its word count.</summary>
    private static readonly TimeSpan CopiedFor = TimeSpan.FromMilliseconds(1_600);

    /// <summary>Below this window width the trailing word counts give up their space.</summary>
    private const double CompactBelow = 1_100;

    /// <summary>The transcript text's leading — two of these is the expanded row.</summary>
    private const double LineHeight = 25;

    /// <summary>How long a delete stays armed after the first click.</summary>
    private static readonly TimeSpan ArmedFor = TimeSpan.FromSeconds(4);

    private readonly IMainWindowActions _actions;
    /// <summary>Opens the window's help popup beside the control that asked for it.</summary>
    private readonly Action<FrameworkElement, PlacementMode> _showHelp;
    private readonly DispatcherTimer _toastTimer = new();
    private readonly List<TextBlock> _wordCounts = [];

    private MainWindowModel? _model;
    private string _query = "";
    private TranscriptSort _sort = TranscriptSort.Newest;
    private bool _isCompact;

    internal TranscriptsPane(IMainWindowActions actions,
                             Action<FrameworkElement, PlacementMode> showHelp)
    {
        _actions = actions;
        _showHelp = showHelp;
        InitializeComponent();
        _toastTimer.Tick += (_, _) => HideToast();
    }

    // MARK: - Input from the window

    internal void Apply(MainWindowModel model, bool rebuildList)
    {
        _model = model;
        Keycap.Text = Spaced(model.Shortcut);
        OnboardingStrip.Visibility = model.ShowsOnboarding ? Visibility.Visible : Visibility.Collapsed;
        StorageLine.Text = TranscriptList.StorageLine(model.History.Records.Count);
        DeleteAllButton.Visibility = model.History.IsEmpty
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (rebuildList) RebuildList();
    }

    /// <summary>The search box lives in the window header; this is what it types.</summary>
    internal void SetQuery(string query)
    {
        if (_query == query) return;
        _query = query;
        RebuildList();
    }

    /// <summary>
    /// A narrow window drops the trailing word counts first — the row's text is
    /// what the list is for.
    /// </summary>
    internal void SetWidth(double width)
    {
        var compact = width < CompactBelow;
        if (compact == _isCompact) return;
        _isCompact = compact;
        foreach (var count in _wordCounts)
            count.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>"Ctrl+Alt+D" → "Ctrl + Alt + D", which is how a keycap reads.</summary>
    private static string Spaced(string shortcut) => shortcut.Replace("+", " + ");

    // MARK: - The list

    private void RebuildList()
    {
        Groups.Children.Clear();
        _wordCounts.Clear();
        if (_model is null) return;

        var list = TranscriptList.Make(_model.History.Records, DateTimeOffset.Now,
                                       query: _query, sort: _sort);
        ShowEmptyState(list.IsEmpty);
        if (list.IsEmpty) return;

        for (var index = 0; index < list.Groups.Count; index += 1)
            Groups.Children.Add(GroupBlock(list.Groups[index], isFirst: index == 0));
    }

    private void ShowEmptyState(bool isEmpty)
    {
        EmptyState.Visibility = isEmpty ? Visibility.Visible : Visibility.Collapsed;
        if (!isEmpty) return;

        var searching = _query.Trim().Length > 0;
        EmptyTitle.Text = searching
            ? $"No transcripts match “{_query.Trim()}”"
            : "Nothing dictated yet";
        EmptyHint.Text = searching
            ? "Press Esc to clear the search."
            : $"Hold {Spaced(_model?.Shortcut ?? "Ctrl+Alt+D")} in any window to start.";
    }

    private UIElement GroupBlock(TranscriptGroup group, bool isFirst)
    {
        var stack = new StackPanel();

        var heading = new DockPanel
        {
            Margin = new Thickness(32, isFirst ? 22 : 26, 32, 10),
        };

        var trailing = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        trailing.Children.Add(new TextBlock
        {
            Text = group.Meta,
            Style = Resource<Style>("MetaLabel"),
            VerticalAlignment = VerticalAlignment.Center,
        });
        // One sort control for the whole list, on the first group only.
        if (isFirst) trailing.Children.Add(SortControl());
        DockPanel.SetDock(trailing, Dock.Right);
        heading.Children.Add(trailing);

        heading.Children.Add(new TextBlock
        {
            Text = group.Label.ToUpperInvariant(),
            Style = Resource<Style>("SectionLabel"),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center,
        });
        stack.Children.Add(heading);

        var rows = new StackPanel { Margin = new Thickness(32, 0, 32, 0) };
        foreach (var row in group.Rows) rows.Children.Add(RowBlock(row));
        stack.Children.Add(rows);
        return stack;
    }

    private UIElement SortControl()
    {
        var button = new Button
        {
            Content = SortLabel(_sort) + " ▾",
            Style = Resource<Style>("LinkButton"),
            FontSize = 13,
            Margin = new Thickness(18, 0, 0, 0),
        };
        button.Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = button, IsOpen = true };
            foreach (var sort in Enum.GetValues<TranscriptSort>())
            {
                var option = new MenuItem { Header = SortLabel(sort), IsChecked = sort == _sort };
                var chosen = sort;
                option.Click += (_, _) =>
                {
                    if (chosen == _sort) return;
                    _sort = chosen;
                    RebuildList();
                };
                menu.Items.Add(option);
            }
        };
        return button;
    }

    private static string SortLabel(TranscriptSort sort) => sort switch
    {
        TranscriptSort.Oldest => "Oldest first",
        TranscriptSort.Longest => "Longest",
        _ => "Newest first",
    };

    private UIElement RowBlock(TranscriptRow row)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(78) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var time = new TextBlock
        {
            Text = row.Time,
            FontFamily = Resource<FontFamily>("Mono"),
            FontSize = 12,
            Foreground = Resource<Brush>("Muted3"),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(time, 0);
        grid.Children.Add(time);

        // One line at rest, two when the pointer or the keyboard is on the row.
        var text = new TextBlock
        {
            Text = row.Text,
            FontFamily = Resource<FontFamily>("Serif"),
            FontSize = 18,
            LineHeight = LineHeight,
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxHeight = 2 * LineHeight,
            Foreground = Resource<Brush>("Ink"),
            Margin = new Thickness(0, 0, 24, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        var count = new TextBlock
        {
            Text = row.Words,
            // Wide enough for "2,140 words" — a fixed slot, so the buttons beside
            // it line up down the list however long the count runs.
            Width = 84,
            TextAlignment = TextAlignment.Right,
            FontFamily = Resource<FontFamily>("Mono"),
            FontSize = 11,
            Foreground = Resource<Brush>("Muted4"),
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = _isCompact ? Visibility.Collapsed : Visibility.Visible,
        };
        _wordCounts.Add(count);

        var actions = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
        };
        actions.Children.Add(count);
        actions.Children.Add(RowButton("Copy", () => Copy(row, count)));
        actions.Children.Add(DeleteButton(row, out var pressDelete));

        Grid.SetColumn(actions, 2);
        grid.Children.Add(actions);

        var shell = new Border
        {
            Background = Brushes.Transparent,
            BorderBrush = Resource<Brush>("BorderRow"),
            BorderThickness = new Thickness(0, 0, 0, 1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12, 16, 12, 16),
            Focusable = true,
            Child = grid,
        };
        Expand(shell, text, hover: Resource<Brush>("Field"));
        shell.PreviewMouseLeftButtonDown += (_, _) => shell.Focus();
        shell.KeyDown += (_, args) => OnRowKey(args, row, count, pressDelete);
        return shell;
    }

    /// <summary>
    /// Hover and keyboard focus do the same two things: tint the row and let its
    /// text run to a second line. WPF has no line limit of its own — wrapping
    /// under a two-line ceiling is what gives the second line and no more.
    /// </summary>
    private static void Expand(Border shell, TextBlock text, Brush hover)
    {
        void Open()
        {
            shell.Background = hover;
            text.TextWrapping = TextWrapping.Wrap;
        }

        void Close()
        {
            if (shell.IsMouseOver || shell.IsKeyboardFocused) return;
            shell.Background = Brushes.Transparent;
            text.TextWrapping = TextWrapping.NoWrap;
        }

        shell.MouseEnter += (_, _) => Open();
        shell.MouseLeave += (_, _) => Close();
        shell.GotKeyboardFocus += (_, _) => Open();
        shell.LostKeyboardFocus += (_, _) => Close();
    }

    private Button RowButton(string label, Action action)
    {
        var button = new Button
        {
            Content = label,
            Style = Resource<Style>("RowButton"),
            Margin = new Thickness(8, 0, 0, 0),
        };
        button.Click += (_, _) => action();
        return button;
    }

    /// <summary>
    /// Deleting takes two clicks. The first arms the button and says so in the
    /// toast; the second acts. A transcript is gone from <c>history.json</c> the
    /// moment it goes, so a stray click must not be enough — and the arming
    /// lapses on its own, so a forgotten one cannot lie in wait.
    /// </summary>
    private Button DeleteButton(TranscriptRow row, out Action press)
    {
        var button = new Button
        {
            Content = "Delete",
            Style = Resource<Style>("RowButtonDestructive"),
            Margin = new Thickness(8, 0, 0, 0),
        };
        var lapse = new DispatcherTimer { Interval = ArmedFor };
        var armed = false;

        void Disarm()
        {
            lapse.Stop();
            armed = false;
            button.Content = "Delete";
            button.Style = Resource<Style>("RowButtonDestructive");
        }

        void Press()
        {
            if (armed)
            {
                Disarm();
                Delete(row);
                return;
            }
            armed = true;
            button.Content = "Delete again";
            button.Style = Resource<Style>("RowButtonArmed");
            ShowToast("Click “Delete again” to remove this transcript", duration: ArmedFor);
            lapse.Stop();
            lapse.Start();
        }

        lapse.Tick += (_, _) => Disarm();
        button.Click += (_, _) => Press();
        press = Press;
        return button;
    }

    private void OnRowKey(KeyEventArgs args, TranscriptRow row, TextBlock count, Action pressDelete)
    {
        switch (args.Key)
        {
            case Key.Enter:
                Copy(row, count);
                break;
            case Key.Delete:
                // The key goes through the button, so it needs the same two presses.
                pressDelete();
                break;
            default:
                return;
        }
        args.Handled = true;
    }

    // MARK: - Row actions

    /// <summary>
    /// The confirmation lands on the row itself, where the click was — the word
    /// count steps aside for a beat and comes back.
    /// </summary>
    private void Copy(TranscriptRow row, TextBlock count)
    {
        _actions.Copy(row.Text);

        var was = count.Text;
        count.Text = "Copied";
        count.Foreground = Resource<Brush>("Green");
        var restore = new DispatcherTimer { Interval = CopiedFor };
        restore.Tick += (_, _) =>
        {
            restore.Stop();
            count.Text = was;
            count.Foreground = Resource<Brush>("Muted4");
        };
        restore.Start();
    }

    private void Delete(TranscriptRow row)
    {
        _actions.Delete(row.Id);
        ShowToast("Transcript deleted", undo: true);
    }

    // MARK: - Toast

    private void ShowToast(string message, bool undo = false, TimeSpan? duration = null)
    {
        ToastLabel.Text = message;
        ToastAction.Visibility = undo ? Visibility.Visible : Visibility.Collapsed;
        Toast.Visibility = Visibility.Visible;
        Toast.BeginAnimation(OpacityProperty, null);
        Toast.Opacity = 1;

        _toastTimer.Stop();
        // An undo needs long enough to be read and reached; a plain note does not.
        _toastTimer.Interval = duration ?? TimeSpan.FromSeconds(undo ? 6 : 2);
        _toastTimer.Start();
    }

    private void HideToast()
    {
        _toastTimer.Stop();
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(220));
        fade.Completed += (_, _) => Toast.Visibility = Visibility.Collapsed;
        Toast.BeginAnimation(OpacityProperty, fade);
    }

    private void OnUndoClicked(object sender, RoutedEventArgs e)
    {
        _actions.UndoDelete();
        HideToast();
    }

    // MARK: - Strip and status bar

    private void OnWalkthroughClicked(object sender, RoutedEventArgs e) =>
        _showHelp((FrameworkElement)sender, PlacementMode.Bottom);

    private void OnChangeShortcutClicked(object sender, RoutedEventArgs e) => _actions.ChangeShortcut();

    private void OnDismissOnboardingClicked(object sender, RoutedEventArgs e)
    {
        OnboardingStrip.Visibility = Visibility.Collapsed;
        _actions.DismissOnboarding();
    }

    private void OnExportAllClicked(object sender, RoutedEventArgs e) => _actions.ExportAll();

    /// <summary>
    /// Deleting every transcript cannot be undone — the history file is rewritten —
    /// so this is the one action that asks first.
    /// </summary>
    private void OnDeleteAllClicked(object sender, RoutedEventArgs e)
    {
        Log.Line("delete-all requested — asking for confirmation");
        var answer = MessageBox.Show(
            "Delete every transcript? This cannot be undone.",
            "Delete all transcripts", MessageBoxButton.YesNo, MessageBoxImage.Warning,
            MessageBoxResult.No);
        Log.Line($"delete-all answer={answer}");
        if (answer == MessageBoxResult.Yes) _actions.DeleteAll();
    }

    // MARK: - Resources

    private static T Resource<T>(string key) => (T)Application.Current.Resources[key];
}
