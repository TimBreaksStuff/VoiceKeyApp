namespace VoiceKey.Core.Tests;

public class VocabularyEditorTests
{
    // MARK: - Loading

    [Fact]
    public void ReplacementRowsAreSortedBySpokenPhrase()
    {
        var editor = MakeEditor(replacements: new()
        {
            ["zebra"] = "Z",
            ["alpha"] = "A",
            ["middle"] = "M",
        });

        Assert.Equal(["alpha", "middle", "zebra"], editor.Replacements.Select(row => row.Spoken));
        Assert.Equal(["A", "M", "Z"], editor.Replacements.Select(row => row.Written));
    }

    [Fact]
    public void TermsKeepTheOrderTheyWereSavedIn()
    {
        var editor = MakeEditor(terms: ["Kubernetes", "VoiceKey", "Herglotz"]);

        Assert.Equal(["Kubernetes", "VoiceKey", "Herglotz"], editor.Terms);
    }

    [Fact]
    public void AnEmptyDictionaryOpensWithNoRows()
    {
        var editor = new VocabularyEditor();

        Assert.Empty(editor.Replacements);
        Assert.Empty(editor.Terms);
    }

    // MARK: - Saving

    [Fact]
    public void EditedRowsRoundTripBackIntoTheDictionary()
    {
        var original = new VocabularyDictionary(
            terms: ["Whisper"],
            replacements: new Dictionary<string, string> { ["get hub"] = "GitHub" });

        Assert.Equal(original, new VocabularyEditor(original).Dictionary);
    }

    [Fact]
    public void AHalfTypedRowIsNotSavedAsARule()
    {
        var editor = MakeEditor(replacements: new() { ["get hub"] = "GitHub" })
            .AddingReplacement()
            .SettingSpoken("jason", 1);

        Assert.Equal(2, editor.Replacements.Count);
        Assert.Equal(Rules(("get hub", "GitHub")), editor.Dictionary);
    }

    [Fact]
    public void BlankTermsAreNotSaved()
    {
        var editor = MakeEditor(terms: ["VoiceKey"]).AddingTerm();

        Assert.Equal(2, editor.Terms.Count);
        Assert.Equal(["VoiceKey"], editor.Dictionary.Terms);
    }

    [Fact]
    public void SurroundingWhitespaceIsTrimmedOnSave()
    {
        var editor = new VocabularyEditor()
            .AddingReplacement()
            .SettingSpoken("  get hub  ", 0)
            .SettingWritten("  GitHub  ", 0)
            .AddingTerm()
            .SettingTerm("  Whisper  ", 0);

        Assert.Equal(Rules(("get hub", "GitHub")).Replacements, editor.Dictionary.Replacements);
        Assert.Equal(["Whisper"], editor.Dictionary.Terms);
    }

    [Fact]
    public void TheFirstOfTwoRowsWithTheSameSpokenPhraseWins()
    {
        var editor = new VocabularyEditor()
            .AddingReplacement().SettingSpoken("jason", 0).SettingWritten("JSON", 0)
            .AddingReplacement().SettingSpoken("Jason", 1).SettingWritten("Jason Bourne", 1);

        Assert.Equal(Rules(("jason", "JSON")), editor.Dictionary);
    }

    [Fact]
    public void DuplicateSpokenPhrasesAreFlaggedForTheUserCaseInsensitively()
    {
        var editor = new VocabularyEditor()
            .AddingReplacement().SettingSpoken("jason", 0).SettingWritten("JSON", 0)
            .AddingReplacement().SettingSpoken(" JASON ", 1).SettingWritten("Jason Bourne", 1)
            .AddingReplacement().SettingSpoken("get hub", 2).SettingWritten("GitHub", 2);

        Assert.Equal([1], editor.IgnoredReplacementRows.Order());
    }

    [Fact]
    public void EmptyRowsAreNotFlaggedAsDuplicatesOfEachOther()
    {
        var editor = new VocabularyEditor().AddingReplacement().AddingReplacement();

        Assert.Empty(editor.IgnoredReplacementRows);
    }

    // MARK: - Editing

    [Fact]
    public void AddingAReplacementAppendsAnEmptyRowAtTheEnd()
    {
        var editor = MakeEditor(replacements: new() { ["get hub"] = "GitHub" }).AddingReplacement();

        Assert.Equal(2, editor.Replacements.Count);
        Assert.Equal(new Replacement("", ""), editor.Replacements[^1]);
    }

    [Fact]
    public void EditingOneRowLeavesTheOthersAlone()
    {
        var editor = MakeEditor(replacements: new() { ["alpha"] = "A", ["beta"] = "B" })
            .SettingWritten("Bravo", 1);

        Assert.Equal(Rules(("alpha", "A"), ("beta", "Bravo")), editor.Dictionary);
    }

    [Fact]
    public void RemovingRowsDropsExactlyTheSelectedOnes()
    {
        var editor = MakeEditor(replacements: new()
        {
            ["alpha"] = "A",
            ["beta"] = "B",
            ["gamma"] = "G",
        }).RemovingReplacements([0, 2]);

        Assert.Equal(Rules(("beta", "B")), editor.Dictionary);
    }

    [Fact]
    public void RemovingTermsDropsExactlyTheSelectedOnes()
    {
        var editor = MakeEditor(terms: ["one", "two", "three"]).RemovingTerms([1]);

        Assert.Equal(["one", "three"], editor.Terms);
    }

    [Fact]
    public void TermsCanBeAddedAndEdited()
    {
        var editor = new VocabularyEditor().AddingTerm().SettingTerm("Kubernetes", 0);

        Assert.Equal(["Kubernetes"], editor.Dictionary.Terms);
    }

    [Fact]
    public void EditsToRowsThatDoNotExistAreIgnored()
    {
        var editor = MakeEditor(replacements: new() { ["alpha"] = "A" }, terms: ["one"]);

        Assert.Equal(editor, editor.SettingSpoken("x", 7));
        Assert.Equal(editor, editor.SettingWritten("x", -1));
        Assert.Equal(editor, editor.SettingTerm("x", 3));
        Assert.Equal(editor, editor.RemovingReplacements([9]));
        Assert.Equal(editor, editor.RemovingTerms([9]));
    }

    // MARK: - Helpers

    private static VocabularyEditor MakeEditor(
        Dictionary<string, string>? replacements = null,
        IReadOnlyList<string>? terms = null) =>
        new(new VocabularyDictionary(terms ?? [], replacements ?? []));

    private static VocabularyDictionary Rules(params (string Spoken, string Written)[] rules) =>
        new(replacements: rules.ToDictionary(rule => rule.Spoken, rule => rule.Written));
}
