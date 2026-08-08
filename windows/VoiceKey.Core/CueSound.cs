namespace VoiceKey.Core;

/// <summary>One note of a cue: a pitch, held for a while.</summary>
public readonly record struct CueTone(double Hertz, int Milliseconds);

/// <summary>
/// The two sounds that say VoiceKey started and stopped listening. Synthesised
/// rather than shipped as files, for the same reason the tray glyph is drawn in
/// code: nothing to lose, nothing to load, and the pitches are readable here.
///
/// The pair is one interval played both ways round — E5 up to B5 to start, back
/// down to start again — so which one you heard needs no learning.
/// </summary>
public static class CueSound
{
    public const int SampleRate = 48_000;

    /// <summary>Well under full scale: this sits behind whatever the user is doing.</summary>
    private const double Amplitude = 0.35;

    private const int FadeInSamples = SampleRate * 4 / 1000;
    private const int FadeOutSamples = SampleRate * 20 / 1000;

    private const double LowNote = 659.25;  // E5
    private const double HighNote = 987.77; // B5

    public static IReadOnlyList<CueTone> Start { get; } =
        [new CueTone(LowNote, 70), new CueTone(HighNote, 90)];

    public static IReadOnlyList<CueTone> Stop { get; } =
        [new CueTone(HighNote, 70), new CueTone(LowNote, 90)];

    /// <summary>
    /// The sidebar footer row that turns the cues off, worded like the launch-at-login
    /// row beside it: the state is the word after the dash.
    /// </summary>
    public static string Label(bool enabled) => $"Sounds — {(enabled ? "On" : "Off")}";

    /// <summary>The tones as a canonical 16-bit mono PCM WAV, header and all.</summary>
    public static byte[] Wav(IReadOnlyList<CueTone> tones)
    {
        var samples = tones.SelectMany(Render).ToArray();
        var dataBytes = samples.Length * sizeof(short);

        using var stream = new MemoryStream(44 + dataBytes);
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8);
        writer.Write(36 + dataBytes);
        writer.Write("WAVE"u8);
        writer.Write("fmt "u8);
        writer.Write(16);                          // PCM header length
        writer.Write((short)1);                    // PCM, uncompressed
        writer.Write((short)1);                    // mono
        writer.Write(SampleRate);
        writer.Write(SampleRate * sizeof(short));  // bytes per second
        writer.Write((short)sizeof(short));        // bytes per frame
        writer.Write((short)16);                   // bits per sample
        writer.Write("data"u8);
        writer.Write(dataBytes);
        foreach (var sample in samples) writer.Write(sample);

        writer.Flush();
        return stream.ToArray();
    }

    private static IEnumerable<short> Render(CueTone tone)
    {
        var count = SampleRate * tone.Milliseconds / 1000;
        return Enumerable.Range(0, count).Select(index =>
            (short)(Math.Sin(2 * Math.PI * tone.Hertz * index / SampleRate)
                    * Amplitude * Fade(index, count) * short.MaxValue));
    }

    /// <summary>
    /// Silent at both ends of every tone. A note that starts or stops mid-cycle
    /// is a step in the waveform, and a step is the click we are avoiding.
    /// </summary>
    private static double Fade(int index, int count)
    {
        var rise = Math.Min(1.0, index / (double)Math.Min(FadeInSamples, count));
        var fall = Math.Min(1.0, (count - 1 - index) / (double)Math.Min(FadeOutSamples, count));
        return Math.Min(rise, fall);
    }
}
