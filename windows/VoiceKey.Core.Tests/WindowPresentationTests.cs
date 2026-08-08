namespace VoiceKey.Core.Tests;

/// <summary>The main window's date line, engine pill, and permission popover.</summary>
public class WindowPresentationTests
{
    // MARK: - Factories

    private static readonly TimeZoneInfo Zone = TimeZoneInfo.Utc;

    /// <summary>Wednesday, 5 August 2026, 15:13 UTC.</summary>
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_785_942_780);

    private static WindowPresentation Present(DictationStatus? status = null,
                                              Grant microphone = Grant.Granted,
                                              Grant model = Grant.Granted) =>
        WindowPresentation.Make(status ?? DictationStatus.Idle, Now, Zone, microphone, model);

    // MARK: - Header

    [Fact]
    public void TheDateLineNamesTheWeekdayAndTheDay()
    {
        Assert.Equal("Wednesday, 5 August", Present().DateLine);
    }

    // MARK: - The engine pill

    [Fact]
    public void ThePillFollowsWhatTheAppIsDoing()
    {
        Assert.Equal("Ready", Present(DictationStatus.Idle).Pill.Label);
        Assert.Equal("Listening…", Present(DictationStatus.Recording(3)).Pill.Label);
        Assert.Equal("Transcribing…", Present(DictationStatus.Transcribing).Pill.Label);
        Assert.Equal("Preparing…", Present(DictationStatus.Loading).Pill.Label);
    }

    [Fact]
    public void EachStateHasItsOwnToneSoTheColourCanBeReadWithoutTheWord()
    {
        Assert.Equal(StatusTone.Ready, Present(DictationStatus.Idle).Pill.Tone);
        Assert.Equal(StatusTone.Listening, Present(DictationStatus.Recording(3)).Pill.Tone);
        Assert.Equal(StatusTone.Working, Present(DictationStatus.Transcribing).Pill.Tone);
        Assert.Equal(StatusTone.Working, Present(DictationStatus.Loading).Pill.Tone);
    }

    [Fact]
    public void AnErrorPillCarriesTheMessageItself()
    {
        var pill = Present(DictationStatus.Error("Microphone blocked")).Pill;

        Assert.Equal("Microphone blocked", pill.Label);
        Assert.Equal(StatusTone.Blocked, pill.Tone);
    }

    [Fact]
    public void OnlyAnErrorPillIsWorthClickingThrough()
    {
        Assert.True(Present(DictationStatus.Error("Microphone blocked")).Pill.IsActionable);
        Assert.False(Present(DictationStatus.Idle).Pill.IsActionable);
        Assert.False(Present(DictationStatus.Recording(1)).Pill.IsActionable);
    }

    // MARK: - Permissions

    [Fact]
    public void EveryPermissionIsListedWithItsState()
    {
        // Windows has no accessibility grant — SendInput needs no permission — so
        // the list is one line shorter than on macOS.
        Assert.Equal(["microphone · granted", "model · loaded"],
            Present().Permissions.Select(line => line.Text));
    }

    [Fact]
    public void AMissingGrantSaysSoAndAsksForAttention()
    {
        var lines = Present(microphone: Grant.Denied, model: Grant.Pending).Permissions;

        Assert.Equal(["microphone · denied", "model · loading"], lines.Select(line => line.Text));
        Assert.Equal([true, true], lines.Select(line => line.NeedsAttention));
    }

    [Fact]
    public void AnUnestablishedGrantReadsAsMissing()
    {
        var lines = Present(microphone: Grant.Unknown, model: Grant.Unknown).Permissions;

        Assert.Equal(["microphone · denied", "model · unavailable"], lines.Select(line => line.Text));
    }

    [Fact]
    public void GrantedPermissionsAskForNothing()
    {
        Assert.Equal([false, false], Present().Permissions.Select(line => line.NeedsAttention));
    }

    [Fact]
    public void EachLineKnowsWhichSubjectItSpeaksForSoItCanBeActedOn()
    {
        Assert.Equal([Subject.Microphone, Subject.Model],
            Present().Permissions.Select(line => line.Subject));
    }

    // MARK: - The onboarding strip

    [Fact]
    public void TheOnboardingStripIsThereForSomeoneWhoHasNotDictatedYet()
    {
        Assert.True(WindowPresentation.ShowsOnboarding(dismissed: false, transcripts: 0));
    }

    [Fact]
    public void DismissingTheStripKeepsItAway()
    {
        Assert.False(WindowPresentation.ShowsOnboarding(dismissed: true, transcripts: 0));
    }

    [Fact]
    public void TheStripRetiresItselfAfterTheThirdDictation()
    {
        Assert.True(WindowPresentation.ShowsOnboarding(dismissed: false, transcripts: 2));
        Assert.False(WindowPresentation.ShowsOnboarding(dismissed: false, transcripts: 3));
    }
}
