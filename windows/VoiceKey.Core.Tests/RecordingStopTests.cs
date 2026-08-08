namespace VoiceKey.Core.Tests;

public class RecordingStopTests
{
    private const int OneSecond = RecordingStop.SampleRate;

    // MARK: - Stopping on silence

    [Fact]
    public void SilenceEndsTheRecordingOnceSpeechHasBeenHeard()
    {
        Assert.True(RecordingStop.ShouldStop(stopsOnSilence: true, heardSpeech: true,
                                             silentSamples: OneSecond, totalSamples: 3 * OneSecond));
    }

    [Fact]
    public void ShorterSilenceIsAPauseForBreathAndKeepsRecording()
    {
        Assert.False(RecordingStop.ShouldStop(stopsOnSilence: true, heardSpeech: true,
                                              silentSamples: OneSecond - 1,
                                              totalSamples: 3 * OneSecond));
    }

    [Fact]
    public void SilenceBeforeAnyoneHasSpokenIsWaiting_NotAnEnding()
    {
        Assert.False(RecordingStop.ShouldStop(stopsOnSilence: false, heardSpeech: false,
                                              silentSamples: 10 * OneSecond,
                                              totalSamples: 10 * OneSecond));
        Assert.False(RecordingStop.ShouldStop(stopsOnSilence: true, heardSpeech: false,
                                              silentSamples: 10 * OneSecond,
                                              totalSamples: 10 * OneSecond));
    }

    // MARK: - The setting that turns it off

    [Fact]
    public void WithTheSettingOffSilenceNeverEndsTheRecording()
    {
        Assert.False(RecordingStop.ShouldStop(stopsOnSilence: false, heardSpeech: true,
                                              silentSamples: 60 * OneSecond,
                                              totalSamples: 90 * OneSecond));
    }

    [Fact]
    public void TheRowCarriesWhetherSilenceWillStopTheRecording()
    {
        Assert.Equal("Stop on silence — On", RecordingStop.Label(true));
        Assert.Equal("Stop on silence — Off", RecordingStop.Label(false));
    }

    // MARK: - The cap that catches a recording nobody stopped

    [Fact]
    public void FiveMinutesEndsTheRecordingEvenWithSilenceStoppingTurnedOff()
    {
        Assert.False(RecordingStop.ShouldStop(stopsOnSilence: false, heardSpeech: true,
                                              silentSamples: 0,
                                              totalSamples: RecordingStop.MaxSamples - 1));
        Assert.True(RecordingStop.ShouldStop(stopsOnSilence: false, heardSpeech: true,
                                             silentSamples: 0,
                                             totalSamples: RecordingStop.MaxSamples));
    }

    [Fact]
    public void TheCapDoesNotWaitForSpeechEither_ItIsAFloorUnderTheBuffer()
    {
        Assert.True(RecordingStop.ShouldStop(stopsOnSilence: false, heardSpeech: false,
                                             silentSamples: RecordingStop.MaxSamples,
                                             totalSamples: RecordingStop.MaxSamples));
    }

    [Fact]
    public void TheCapIsFiveMinutesOfSixteenKilohertzAudio()
    {
        Assert.Equal(5 * 60 * 16_000, RecordingStop.MaxSamples);
    }
}
