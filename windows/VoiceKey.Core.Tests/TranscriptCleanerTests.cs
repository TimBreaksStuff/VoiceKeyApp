using VoiceKey.Core;

namespace VoiceKey.Core.Tests;

public class TranscriptCleanerTests
{
    // MARK: - Filler removal

    [Fact]
    public void RemovesStandaloneFillersAlongWithTheirTrailingComma()
    {
        // A filler swallows the comma that directly follows it; the punctuation
        // that belonged to the surrounding sentence is left alone.
        Assert.Equal("So, I think we should, ship it.",
            TranscriptCleaner.Clean("So, um, I think we should, uh, ship it."));
    }

    [Fact]
    public void RemovesFillersRegardlessOfCase()
    {
        Assert.Equal("I think so", TranscriptCleaner.Clean("I UH think Er so"));
        Assert.Equal("Well maybe later", TranscriptCleaner.Clean("Well Umm maybe Mhm later"));
    }

    [Fact]
    public void RemovesEveryRecognisedFillerSpelling()
    {
        Assert.Equal("one two three four five six seven eight",
            TranscriptCleaner.Clean("one um two uh three uhm four umm five er six erm seven mhm eight"));
    }

    [Fact]
    public void RemovesFillerTogetherWithATrailingEllipsis()
    {
        Assert.Equal("Well maybe later", TranscriptCleaner.Clean("Well um ... maybe later"));
        Assert.Equal("Well maybe later", TranscriptCleaner.Clean("Well uh… maybe later"));
    }

    [Fact]
    public void LeavesWordsThatMerelyContainFillerSubstringsIntact()
    {
        Assert.Equal("The umbrella and her summer termite.",
            TranscriptCleaner.Clean("The umbrella and her summer termite."));
    }

    [Fact]
    public void LeavesAnAlreadyCleanTranscriptUnchanged()
    {
        Assert.Equal("The quick brown fox jumps over the lazy dog.",
            TranscriptCleaner.Clean("The quick brown fox jumps over the lazy dog."));
    }

    // MARK: - Sentence-start fillers

    [Fact]
    public void CapitalisesTheFollowingWordWhenAFillerOpensASentence()
    {
        Assert.Equal("Hello there.", TranscriptCleaner.Clean("Um, hello there."));
        Assert.Equal("I said no. Maybe later.", TranscriptCleaner.Clean("I said no. Uh, maybe later."));
    }

    [Fact]
    public void SentenceStartCapitalisationUppercasesCamelCasedWordsToo()
    {
        // Accepted edge case: the rule cannot know that "iPhone" is deliberately
        // lowercase, so it becomes "IPhone". Not special-cased on purpose.
        Assert.Equal("IPhone users complain.", TranscriptCleaner.Clean("Um, iPhone users complain."));
    }

    [Fact]
    public void SentenceStartFillerIsStillRemovedWhenTheFollowingWordIsAlreadyCapitalised()
    {
        Assert.Equal("I think so.", TranscriptCleaner.Clean("Um, I think so."));
    }

    // MARK: - Stumble collapse

    [Fact]
    public void CollapsesImmediateWordRepetitions()
    {
        Assert.Equal("the report", TranscriptCleaner.Clean("the the report"));
        Assert.Equal("I think so", TranscriptCleaner.Clean("I I think so"));
    }

    [Fact]
    public void CollapsesRepetitionsCaseInsensitivelyKeepingTheFirstSpelling()
    {
        Assert.Equal("The report", TranscriptCleaner.Clean("The the report"));
    }

    [Fact]
    public void CollapsesRunsOfMoreThanTwoRepetitions()
    {
        Assert.Equal("It was very good", TranscriptCleaner.Clean("It was very very very good"));
    }

    [Fact]
    public void CollapsesRepetitionsThatOnlyAppearAfterFillerRemoval()
    {
        Assert.Equal("the report", TranscriptCleaner.Clean("the um the report"));
    }

    [Fact]
    public void DoesNotCollapseRepetitionsSeparatedByPunctuation()
    {
        Assert.Equal("No, no, never.", TranscriptCleaner.Clean("No, no, never."));
        Assert.Equal("Stop. Stop now.", TranscriptCleaner.Clean("Stop. Stop now."));
    }

    [Fact]
    public void CollapsesLegitimateDoubledWordsAsAnAcceptedTradeoff()
    {
        // "had had" is grammatical, but bare adjacent repeats are collapsed
        // unconditionally — mis-collapsing this is preferred over keeping stutters.
        Assert.Equal("She had enough", TranscriptCleaner.Clean("She had had enough"));
    }

    // MARK: - Whitespace

    [Fact]
    public void NormalisesWhitespaceRunsAndTrimsTheResult()
    {
        Assert.Equal("Hello world", TranscriptCleaner.Clean("  Hello    world  "));
        Assert.Equal("Hello world", TranscriptCleaner.Clean("Hello\tworld"));
    }

    [Fact]
    public void ReturnsEmptyStringForBlankInput()
    {
        Assert.Equal("", TranscriptCleaner.Clean(""));
        Assert.Equal("", TranscriptCleaner.Clean("   "));
        Assert.Equal("", TranscriptCleaner.Clean(" \n\t "));
    }

    [Fact]
    public void PreservesNewlinesSoParagraphStructureSurvives()
    {
        Assert.Equal("First line\nSecond line",
            TranscriptCleaner.Clean("First line um  \n  Second   line"));
        // A word ending one line and opening the next is not a stutter — collapsing
        // it would silently swallow the line break.
        Assert.Equal("Send it\nit was fine", TranscriptCleaner.Clean("Send it\nit was fine"));
    }

    // MARK: - Non-speech annotations

    [Fact]
    public void IdentifiesTranscriptsThatAreEntirelyANonSpeechAnnotation()
    {
        Assert.True(TranscriptCleaner.IsNonSpeechAnnotation("[wind howling]"));
        Assert.True(TranscriptCleaner.IsNonSpeechAnnotation("(music)"));
        Assert.True(TranscriptCleaner.IsNonSpeechAnnotation("[BLANK_AUDIO]"));
        Assert.True(TranscriptCleaner.IsNonSpeechAnnotation("  [music]  "));
    }

    [Fact]
    public void RejectsTranscriptsThatAreNotPurelyAnAnnotation()
    {
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation("Hello there."));
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation(""));
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation("   "));
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation("Hello [music] there"));
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation("[music] and then talking"));
        Assert.False(TranscriptCleaner.IsNonSpeechAnnotation("[]"));
    }
}
