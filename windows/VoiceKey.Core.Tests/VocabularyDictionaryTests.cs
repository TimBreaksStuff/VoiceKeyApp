namespace VoiceKey.Core.Tests;

public class VocabularyDictionaryTests
{
    // MARK: - Replacements

    [Fact]
    public void ReplacementMatchesWholeWordCaseInsensitively()
    {
        var dictionary = MakeDictionary(replacements: new() { ["get hub"] = "GitHub" });

        Assert.Equal("I pushed to GitHub today",
            dictionary.ApplyingReplacements("I pushed to get hub today"));
        Assert.Equal("GitHub is down.",
            dictionary.ApplyingReplacements("Get hub is down."));
    }

    [Fact]
    public void ReplacementDoesNotMatchInsideLargerWord()
    {
        var dictionary = MakeDictionary(replacements: new() { ["get hub"] = "GitHub" });

        Assert.Equal("a target hubcap", dictionary.ApplyingReplacements("a target hubcap"));
    }

    [Fact]
    public void MultiWordPhraseKeyIsReplaced()
    {
        var dictionary = MakeDictionary(replacements: new() { ["large language model"] = "LLM" });

        Assert.Equal("the LLM wrote it",
            dictionary.ApplyingReplacements("the large language model wrote it"));
    }

    [Fact]
    public void ReplacementValueKeepsItsOwnCasing()
    {
        var dictionary = MakeDictionary(replacements: new() { ["jason"] = "JSON" });

        Assert.Equal("JSON and JSON", dictionary.ApplyingReplacements("Jason and jason"));
    }

    [Fact]
    public void KeysWithRegexMetacharactersAreTreatedLiterally()
    {
        var dictionary = MakeDictionary(replacements: new()
        {
            ["c++"] = "C++",
            ["node.js"] = "Node.js",
        });

        Assert.Equal("I write C++ and Node.js",
            dictionary.ApplyingReplacements("I write c++ and node.js"));
        Assert.Equal("nodexjs stays", dictionary.ApplyingReplacements("nodexjs stays"));
    }

    [Fact]
    public void ReplacementOutputIsNeverRematchedByAnotherRule()
    {
        var dictionary = MakeDictionary(replacements: new()
        {
            ["alpha"] = "beta",
            ["beta"] = "gamma",
        });

        Assert.Equal("beta and gamma", dictionary.ApplyingReplacements("alpha and beta"));
    }

    [Fact]
    public void LongerKeyWinsOverOverlappingShorterKey()
    {
        var dictionary = MakeDictionary(replacements: new()
        {
            ["visual studio"] = "Visual Studio",
            ["visual studio code"] = "VS Code",
        });

        Assert.Equal("open VS Code now",
            dictionary.ApplyingReplacements("open visual studio code now"));
        Assert.Equal("open Visual Studio now",
            dictionary.ApplyingReplacements("open visual studio now"));
    }

    [Fact]
    public void ReplacementSurvivesNonAsciiTextAroundMatches()
    {
        var dictionary = MakeDictionary(replacements: new() { ["jason"] = "JSON" });

        Assert.Equal("🎤 JSON, café JSON — JSON",
            dictionary.ApplyingReplacements("🎤 jason, café jason — jason"));
    }

    [Fact]
    public void EmptyReplacementsLeaveTextUnchanged()
    {
        const string text = "nothing to see here";

        Assert.Equal(text, MakeDictionary().ApplyingReplacements(text));
    }

    // MARK: - Prompt text

    [Fact]
    public void PromptTextIsNullWithoutTerms()
    {
        Assert.Null(MakeDictionary().PromptText);
    }

    [Fact]
    public void PromptTextIsSingleLineMentioningEveryTerm()
    {
        string[] terms = ["GitHub", "Kubernetes", "Herglotz"];
        var dictionary = MakeDictionary(terms: terms);

        var prompt = dictionary.PromptText;

        Assert.NotNull(prompt);
        Assert.All(terms, term => Assert.Contains(term, prompt));
        Assert.DoesNotContain("\n", prompt);
    }

    // MARK: - Persistence

    [Fact]
    public void LoadReturnsNullForMissingFile()
    {
        var path = MakeTemporaryPath();

        Assert.Null(VocabularyDictionary.Load(path));
    }

    [Fact]
    public void LoadReturnsNullForMalformedJson()
    {
        var path = MakeTemporaryPath();
        try
        {
            File.WriteAllText(path, "{ this is not json");

            Assert.Null(VocabularyDictionary.Load(path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void SaveThenLoadRoundTripsTheDictionary()
    {
        var original = MakeDictionary(
            terms: ["WhisperKit", "Herglotz"],
            replacements: new() { ["get hub"] = "GitHub", ["jason"] = "JSON" });
        var path = MakeTemporaryPath();
        try
        {
            original.Save(path);

            Assert.Equal(original, VocabularyDictionary.Load(path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void SavedFileIsPrettyPrintedWithSortedKeys()
    {
        var path = MakeTemporaryPath();
        try
        {
            MakeDictionary(replacements: new() { ["zebra"] = "Z", ["alpha"] = "A" }).Save(path);

            var json = File.ReadAllText(path);

            Assert.Contains("\n", json);
            Assert.Contains("  ", json);
            Assert.InRange(json.IndexOf("alpha", StringComparison.Ordinal),
                0, json.IndexOf("zebra", StringComparison.Ordinal) - 1);
        }
        finally { File.Delete(path); }
    }

    // MARK: - Template

    [Fact]
    public void TemplateDocumentsTheSchemaByExample()
    {
        var template = VocabularyDictionary.Template;

        Assert.NotEmpty(template.Terms);
        Assert.NotEmpty(template.Replacements);
    }

    [Fact]
    public void TemplateReplacementsActuallyApply()
    {
        var template = VocabularyDictionary.Template;

        var (spoken, written) = template.Replacements.First();

        Assert.Equal(written, template.ApplyingReplacements(spoken));
    }

    // MARK: - Suggesting a term from a transcript

    [Fact]
    public void AShortTranscriptIsOfferedAsATermReadyToKeep()
    {
        Assert.Equal("Kubernetes", VocabularyDictionary.SuggestedTerm("Kubernetes"));
        Assert.Equal("Voice Key", VocabularyDictionary.SuggestedTerm("  Voice Key  "));
    }

    [Fact]
    public void ASuggestedTermReadsAsOneLine()
    {
        Assert.Equal("Voice Key", VocabularyDictionary.SuggestedTerm("Voice\nKey"));
    }

    [Fact]
    public void AWholeSentenceIsNoTermSoNothingIsSuggested()
    {
        Assert.Null(VocabularyDictionary.SuggestedTerm("Rebase onto main, then force push."));
        Assert.Null(VocabularyDictionary.SuggestedTerm("   "));
    }

    // MARK: - Helpers

    private static VocabularyDictionary MakeDictionary(
        IReadOnlyList<string>? terms = null,
        Dictionary<string, string>? replacements = null) =>
        new(terms ?? [], replacements ?? []);

    private static string MakeTemporaryPath() =>
        Path.Combine(Path.GetTempPath(), $"VocabularyDictionaryTests-{Guid.NewGuid()}.json");
}
