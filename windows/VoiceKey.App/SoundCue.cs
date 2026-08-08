using System.Media;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// Plays the two cues from <see cref="CueSound"/> on the default output device.
/// The WAV bytes are synthesised once and held, so a cue costs no disk and no
/// allocation at the moment the shortcut is pressed.
/// </summary>
internal static class SoundCue
{
    private static readonly SoundPlayer Started = Player(CueSound.Start);
    private static readonly SoundPlayer Stopped = Player(CueSound.Stop);

    internal static void RecordingStarted() => Started.Play();

    internal static void RecordingStopped() => Stopped.Play();

    private static SoundPlayer Player(IReadOnlyList<CueTone> tones)
    {
        var player = new SoundPlayer(new MemoryStream(CueSound.Wav(tones)));
        player.Load();
        return player;
    }
}
