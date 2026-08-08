namespace VoiceKey.Core.Tests;

public class StatusPresentationTests
{
    private static StatusPresentation Present(DictationStatus status,
                                              string shortcut = "Ctrl+Alt+D",
                                              string model = "ggml-small.en") =>
        StatusPresentation.Make(status, shortcut, model);

    // MARK: - Settling

    [Fact]
    public void SettlingWithAWorkingShortcutIsPlainlyIdle()
    {
        Assert.Equal(DictationStatus.Idle, DictationStatus.Settled(true, "Ctrl+Alt+D"));
    }

    [Fact]
    public void SettlingWithAShortcutThatNeverBoundSaysSoInsteadOfClaimingReady()
    {
        Assert.Equal(DictationStatus.Error("Ctrl+Alt+D is taken by another app"),
            DictationStatus.Settled(false, "Ctrl+Alt+D"));
    }

    // MARK: - Titles

    [Fact]
    public void EachStateNamesItselfInOneOrTwoWords()
    {
        Assert.Equal("Preparing model", Present(DictationStatus.Loading).Title);
        Assert.Equal("Ready", Present(DictationStatus.Idle).Title);
        Assert.Equal("Recording", Present(DictationStatus.Recording(0)).Title);
        Assert.Equal("Transcribing", Present(DictationStatus.Transcribing).Title);
    }

    [Fact]
    public void ErrorStateShowsTheMessageAsItsTitle()
    {
        Assert.Equal("Microphone access denied",
            Present(DictationStatus.Error("Microphone access denied")).Title);
    }

    // MARK: - Meta column

    [Fact]
    public void IdleMetaShowsTheShortcutAndHowToUseIt()
    {
        Assert.Equal("Ctrl+Alt+D hold", Present(DictationStatus.Idle, shortcut: "Ctrl+Alt+D").Meta);
        Assert.Equal("Win+Shift+Space hold",
            Present(DictationStatus.Idle, shortcut: "Win+Shift+Space").Meta);
    }

    [Fact]
    public void RecordingMetaCountsElapsedTimeAsMinutesAndSeconds()
    {
        Assert.Equal("0:00", Present(DictationStatus.Recording(0)).Meta);
        Assert.Equal("0:07", Present(DictationStatus.Recording(7)).Meta);
        Assert.Equal("1:05", Present(DictationStatus.Recording(65)).Meta);
        Assert.Equal("10:00", Present(DictationStatus.Recording(600)).Meta);
    }

    [Fact]
    public void RecordingMetaNeverShowsNegativeTime()
    {
        Assert.Equal("0:00", Present(DictationStatus.Recording(-3)).Meta);
    }

    [Fact]
    public void ModelStatesNameTheModelWithoutItsFilePrefix()
    {
        Assert.Equal("small.en", Present(DictationStatus.Transcribing).Meta);
        Assert.Equal("small.en", Present(DictationStatus.Loading).Meta);
    }

    [Fact]
    public void ModelNameWithoutAPrefixIsShownVerbatim()
    {
        Assert.Equal("tiny.en", Present(DictationStatus.Transcribing, model: "tiny.en").Meta);
    }

    [Fact]
    public void ErrorStateHasNoMeta()
    {
        Assert.Equal("", Present(DictationStatus.Error("Model load failed")).Meta);
    }

    // MARK: - Action item

    [Fact]
    public void ActionMatchesWhatThePrimaryItemWouldDo()
    {
        Assert.Equal("Start Dictation", Present(DictationStatus.Loading).Action);
        Assert.Equal("Start Dictation", Present(DictationStatus.Idle).Action);
        Assert.Equal("Stop Dictation", Present(DictationStatus.Recording(0)).Action);
        Assert.Equal("Stop Dictation", Present(DictationStatus.Transcribing).Action);
        Assert.Equal("Retry", Present(DictationStatus.Error("nope")).Action);
    }

    // MARK: - Glyph

    [Fact]
    public void OnlyLiveStatesUseTheFilledGlyph()
    {
        Assert.Equal(Glyph.Recording, Present(DictationStatus.Recording(0)).Glyph);
        Assert.Equal(Glyph.Recording, Present(DictationStatus.Transcribing).Glyph);
        Assert.Equal(Glyph.Idle, Present(DictationStatus.Idle).Glyph);
        Assert.Equal(Glyph.Idle, Present(DictationStatus.Loading).Glyph);
        Assert.Equal(Glyph.Idle, Present(DictationStatus.Error("nope")).Glyph);
    }

    [Fact]
    public void StatesTheUserCannotDictateInAreDimmed()
    {
        Assert.True(Present(DictationStatus.Loading).IsDimmed);
        Assert.True(Present(DictationStatus.Error("nope")).IsDimmed);
        Assert.False(Present(DictationStatus.Idle).IsDimmed);
        Assert.False(Present(DictationStatus.Recording(0)).IsDimmed);
        Assert.False(Present(DictationStatus.Transcribing).IsDimmed);
    }
}
