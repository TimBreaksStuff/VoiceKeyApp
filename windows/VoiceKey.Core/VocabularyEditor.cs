namespace VoiceKey.Core;

/// <summary>One "when I say X, type Y" row. Either half may be blank while editing.</summary>
public sealed record Replacement(string Spoken = "", string Written = "")
{
    internal bool IsComplete =>
        !string.IsNullOrWhiteSpace(Spoken) && !string.IsNullOrWhiteSpace(Written);
}

/// <summary>
/// The dictionary as an editable list of rows — what the Dictionary pane shows
/// and edits, and the only place that knows how rows become a <see cref="VocabularyDictionary"/>.
///
/// Rows exist because <see cref="VocabularyDictionary.Replacements"/> is an unordered map: a
/// table needs stable positions, and a row being edited is allowed to be blank or
/// duplicated for as long as the user is typing. Nothing invalid reaches disk —
/// <see cref="Dictionary"/> is the filter.
/// </summary>
public sealed class VocabularyEditor : IEquatable<VocabularyEditor>
{
    public IReadOnlyList<Replacement> Replacements { get; }
    public IReadOnlyList<string> Terms { get; }

    public VocabularyEditor() : this(new VocabularyDictionary()) { }

    public VocabularyEditor(VocabularyDictionary dictionary)
    {
        Replacements = dictionary.Replacements
            .OrderBy(entry => entry.Key, StringComparer.OrdinalIgnoreCase)
            .Select(entry => new Replacement(entry.Key, entry.Value))
            .ToArray();
        Terms = dictionary.Terms;
    }

    private VocabularyEditor(IReadOnlyList<Replacement> replacements, IReadOnlyList<string> terms)
    {
        Replacements = replacements;
        Terms = terms;
    }

    /// <summary>
    /// The saveable dictionary: blank halves and rows shadowed by an earlier row
    /// with the same spoken phrase are dropped, so what the user sees first wins.
    /// </summary>
    public VocabularyDictionary Dictionary
    {
        get
        {
            var ignored = IgnoredReplacementRows;
            var rules = Replacements
                .Select((row, index) => (row, index))
                .Where(entry => entry.row.IsComplete && !ignored.Contains(entry.index))
                .ToDictionary(entry => entry.row.Spoken.Trim(), entry => entry.row.Written.Trim());
            return new VocabularyDictionary(
                Terms.Select(term => term.Trim()).Where(term => term.Length > 0).ToArray(),
                rules);
        }
    }

    /// <summary>
    /// Rows that will not take effect because an earlier row already claims the
    /// same spoken phrase — matching is case-insensitive, so replacing is too.
    /// </summary>
    public IReadOnlySet<int> IgnoredReplacementRows
    {
        get
        {
            var claimed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var ignored = new HashSet<int>();
            for (var index = 0; index < Replacements.Count; index++)
            {
                var spoken = Replacements[index].Spoken.Trim();
                if (spoken.Length == 0) continue;
                if (!claimed.Add(spoken)) ignored.Add(index);
            }
            return ignored;
        }
    }

    // MARK: - Editing

    public VocabularyEditor AddingReplacement() =>
        new([.. Replacements, new Replacement()], Terms);

    public VocabularyEditor SettingSpoken(string text, int index) =>
        UpdatingReplacement(index, row => row with { Spoken = text });

    public VocabularyEditor SettingWritten(string text, int index) =>
        UpdatingReplacement(index, row => row with { Written = text });

    public VocabularyEditor RemovingReplacements(IEnumerable<int> indexes) =>
        new(Removing(Replacements, indexes), Terms);

    public VocabularyEditor AddingTerm() => new(Replacements, [.. Terms, ""]);

    public VocabularyEditor SettingTerm(string text, int index)
    {
        if (index < 0 || index >= Terms.Count) return this;
        var updated = Terms.ToArray();
        updated[index] = text;
        return new VocabularyEditor(Replacements, updated);
    }

    public VocabularyEditor RemovingTerms(IEnumerable<int> indexes) =>
        new(Replacements, Removing(Terms, indexes));

    private VocabularyEditor UpdatingReplacement(int index, Func<Replacement, Replacement> edit)
    {
        if (index < 0 || index >= Replacements.Count) return this;
        var updated = Replacements.ToArray();
        updated[index] = edit(updated[index]);
        return new VocabularyEditor(updated, Terms);
    }

    private static T[] Removing<T>(IReadOnlyList<T> items, IEnumerable<int> indexes)
    {
        var dropped = indexes.ToHashSet();
        return items.Where((_, index) => !dropped.Contains(index)).ToArray();
    }

    // MARK: - Equality

    public bool Equals(VocabularyEditor? other) =>
        other is not null
        && Replacements.SequenceEqual(other.Replacements)
        && Terms.SequenceEqual(other.Terms);

    public override bool Equals(object? obj) => Equals(obj as VocabularyEditor);

    public override int GetHashCode() => HashCode.Combine(Replacements.Count, Terms.Count);
}
