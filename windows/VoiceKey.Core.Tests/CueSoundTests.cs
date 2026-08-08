namespace VoiceKey.Core.Tests;

public class CueSoundTests
{
    // MARK: - What the two cues sound like

    [Fact]
    public void StartRisesAndStopFallsSoTheDirectionAloneSaysWhichHappened()
    {
        Assert.Equal(2, CueSound.Start.Count);
        Assert.Equal(2, CueSound.Stop.Count);
        Assert.True(CueSound.Start[1].Hertz > CueSound.Start[0].Hertz);
        Assert.True(CueSound.Stop[1].Hertz < CueSound.Stop[0].Hertz);
    }

    [Fact]
    public void StopIsTheSameTwoNotesAsStartInTheOtherOrder()
    {
        Assert.Equal(CueSound.Start.Select(tone => tone.Hertz).OrderBy(hertz => hertz),
                     CueSound.Stop.Select(tone => tone.Hertz).OrderBy(hertz => hertz));
    }

    [Fact]
    public void BothCuesAreShortEnoughToPassForFeedbackRatherThanMusic()
    {
        Assert.InRange(CueSound.Start.Sum(tone => tone.Milliseconds), 1, 250);
        Assert.InRange(CueSound.Stop.Sum(tone => tone.Milliseconds), 1, 250);
    }

    // MARK: - The row that turns them off

    [Fact]
    public void TheRowCarriesWhetherTheCuesWillPlay()
    {
        Assert.Equal("Sounds — On", CueSound.Label(true));
        Assert.Equal("Sounds — Off", CueSound.Label(false));
    }

    // MARK: - The rendered WAV

    [Fact]
    public void RendersACanonicalSixteenBitMonoWavAtTheStatedSampleRate()
    {
        var wav = CueSound.Wav([new CueTone(1000, 100)]);

        Assert.Equal("RIFF", Text(wav, 0));
        Assert.Equal("WAVE", Text(wav, 8));
        Assert.Equal("fmt ", Text(wav, 12));
        Assert.Equal(16, BitConverter.ToInt32(wav, 16));         // PCM fmt chunk size
        Assert.Equal(1, BitConverter.ToInt16(wav, 20));          // format 1 = PCM
        Assert.Equal(1, BitConverter.ToInt16(wav, 22));          // mono
        Assert.Equal(CueSound.SampleRate, BitConverter.ToInt32(wav, 24));
        Assert.Equal(16, BitConverter.ToInt16(wav, 34));         // bits per sample
        Assert.Equal("data", Text(wav, 36));
    }

    [Fact]
    public void TheHeadersTwoLengthsDescribeTheSamplesThatFollow()
    {
        var wav = CueSound.Wav([new CueTone(1000, 100)]);

        Assert.Equal(wav.Length - 8, BitConverter.ToInt32(wav, 4));
        Assert.Equal(wav.Length - 44, BitConverter.ToInt32(wav, 40));
    }

    [Fact]
    public void HoldsEveryToneForAsLongAsItAsksFor()
    {
        Assert.Equal(CueSound.SampleRate * 150 / 1000, Samples(CueSound.Wav([new CueTone(440, 150)])).Length);
        Assert.Equal(CueSound.SampleRate * 180 / 1000,
                     Samples(CueSound.Wav([new CueTone(440, 60), new CueTone(660, 120)])).Length);
    }

    [Fact]
    public void ATonesPitchIsThePitchItWasAskedFor()
    {
        var samples = Samples(CueSound.Wav([new CueTone(1000, 200)]));

        // 1000 Hz for 0.2s crosses zero twice per cycle: 400 crossings, give or
        // take the fades at either end.
        Assert.InRange(ZeroCrossings(samples), 396, 404);
    }

    [Fact]
    public void OpensAndClosesOnSilenceSoNeitherEndClicks()
    {
        var samples = Samples(CueSound.Wav(CueSound.Start));

        Assert.Equal(0, samples[0]);
        Assert.Equal(0, samples[^1]);
    }

    [Fact]
    public void StaysWellShortOfFullScaleBecauseThisIsACueNotAnAlarm()
    {
        var loudest = Samples(CueSound.Wav(CueSound.Start)).Max(Math.Abs);

        Assert.InRange(loudest, short.MaxValue / 10, short.MaxValue / 2);
    }

    // MARK: - Helpers

    private static string Text(byte[] wav, int offset) =>
        System.Text.Encoding.ASCII.GetString(wav, offset, 4);

    private static short[] Samples(byte[] wav) =>
        Enumerable.Range(0, (wav.Length - 44) / 2)
                  .Select(index => BitConverter.ToInt16(wav, 44 + index * 2))
                  .ToArray();

    private static int ZeroCrossings(short[] samples) =>
        Enumerable.Range(1, samples.Length - 1)
                  .Count(index => samples[index - 1] < 0 != samples[index] < 0);
}
