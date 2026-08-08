using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Controls;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// The Dictionary pane — two editable tables over <see cref="VocabularyEditor"/>,
/// saved after every committed edit. Table glue only: what is saveable, and which
/// row is shadowed by an earlier one, is decided in VoiceKey.Core.
/// </summary>
public partial class DictionaryPane : UserControl
{
    internal sealed class TermRow(string text)
    {
        public string Text { get; set; } = text;
    }

    internal sealed class ReplacementRow(string spoken, string written) : INotifyPropertyChanged
    {
        public string Spoken { get; set; } = spoken;
        public string Written { get; set; } = written;

        private bool _isShadowed;
        public bool IsShadowed
        {
            get => _isShadowed;
            set
            {
                if (_isShadowed == value) return;
                _isShadowed = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsShadowed)));
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
    }

    private readonly ObservableCollection<TermRow> _terms = [];
    private readonly ObservableCollection<ReplacementRow> _replacements = [];
    /// <summary>Told after every save, so the sidebar's entry count keeps up.</summary>
    private readonly Action _onSaved;

    internal DictionaryPane(Action onSaved)
    {
        _onSaved = onSaved;
        InitializeComponent();
        TermsGrid.ItemsSource = _terms;
        ReplacementsGrid.ItemsSource = _replacements;
        PathLabel.Text = Storage.Dictionary;
        Reload();
    }

    /// <summary>Re-reads the file, so an edit made outside the app is picked up.</summary>
    internal void Reload()
    {
        var editor = new VocabularyEditor(
            VocabularyDictionary.Load(Storage.Dictionary) ?? VocabularyDictionary.Template);

        _terms.Clear();
        foreach (var term in editor.Terms) _terms.Add(new TermRow(term));

        _replacements.Clear();
        foreach (var row in editor.Replacements)
            _replacements.Add(new ReplacementRow(row.Spoken, row.Written));

        MarkShadowedRows(editor);
    }

    /// <summary>Adds a term row, pre-filled from a transcript when there is one worth offering.</summary>
    internal void AddTerm(string? suggestion)
    {
        _terms.Add(new TermRow(suggestion ?? ""));
        TermsGrid.SelectedIndex = _terms.Count - 1;
        Save();
    }

    // MARK: - Editing

    private void OnAddTerm(object sender, System.Windows.RoutedEventArgs e) => AddTerm(null);

    private void OnRemoveTerms(object sender, System.Windows.RoutedEventArgs e)
    {
        foreach (var row in TermsGrid.SelectedItems.OfType<TermRow>().ToArray()) _terms.Remove(row);
        Save();
    }

    private void OnAddReplacement(object sender, System.Windows.RoutedEventArgs e)
    {
        _replacements.Add(new ReplacementRow("", ""));
        ReplacementsGrid.SelectedIndex = _replacements.Count - 1;
        Save();
    }

    private void OnRemoveReplacements(object sender, System.Windows.RoutedEventArgs e)
    {
        foreach (var row in ReplacementsGrid.SelectedItems.OfType<ReplacementRow>().ToArray())
            _replacements.Remove(row);
        Save();
    }

    /// <summary>
    /// The grid commits the edited cell after this event returns, so the save has
    /// to wait a beat for the value to reach the row.
    /// </summary>
    private void OnCellEdited(object? sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction != DataGridEditAction.Commit) return;
        Dispatcher.BeginInvoke(Save);
    }

    // MARK: - Saving

    /// <summary>
    /// Rows → <see cref="VocabularyEditor"/> → disk. Blank halves stay on screen but
    /// are never written, and of two rows with the same spoken phrase the first wins.
    /// </summary>
    private void Save()
    {
        var editor = new VocabularyEditor();
        foreach (var row in _replacements)
        {
            var index = editor.Replacements.Count;
            editor = editor.AddingReplacement()
                .SettingSpoken(row.Spoken, index)
                .SettingWritten(row.Written, index);
        }
        foreach (var term in _terms)
            editor = editor.AddingTerm().SettingTerm(term.Text, editor.Terms.Count - 1);

        MarkShadowedRows(editor);
        try
        {
            editor.Dictionary.Save(Storage.Dictionary);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Log.Line($"dictionary save FAILED: {exception.Message}");
        }
        _onSaved();
    }

    private void MarkShadowedRows(VocabularyEditor editor)
    {
        var ignored = editor.IgnoredReplacementRows;
        for (var index = 0; index < _replacements.Count; index++)
            _replacements[index].IsShadowed = ignored.Contains(index);
    }
}
