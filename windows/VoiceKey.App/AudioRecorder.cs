using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// Taps the microphone at its native format, resamples to 16 kHz mono float
/// (what whisper wants), and stops itself when <see cref="RecordingStop"/> says
/// the recording has ended — trailing silence, or the cap.
/// </summary>
internal sealed class AudioRecorder : IDisposable
{
    /// <summary>RMS below this is silence. Same threshold as the macOS build.</summary>
    private const float SpeechRms = 0.015f;
    private const int TargetRate = RecordingStop.SampleRate;

    /// <summary>
    /// Guards the capture chain, which the WPF thread starts and stops while a
    /// WASAPI thread feeds it.
    /// </summary>
    private readonly Lock _gate = new();

    private WasapiCapture? _capture;
    private BufferedWaveProvider? _incoming;
    private ISampleProvider? _resampled;
    private readonly List<float> _samples = [];
    private readonly float[] _pullBuffer = new float[8_192];
    private bool _heardSpeech;
    private int _silentSampleCount;
    private bool _autoStopFired;
    private bool _stopOnSilence = true;

    /// <summary>Fired at most once per recording, from a capture thread.</summary>
    internal Action? OnAutoStop { get; set; }

    /// <param name="stopOnSilence">
    /// The user's setting: false leaves the recording running through any pause,
    /// so only a second press of the shortcut (or the cap) ends it.
    /// </param>
    internal void Start(bool stopOnSilence)
    {
        Stop();

        var capture = new WasapiCapture();
        Log.Line($"mic input format {capture.WaveFormat}");
        var incoming = new BufferedWaveProvider(capture.WaveFormat)
        {
            BufferDuration = TimeSpan.FromSeconds(10),
            DiscardOnBufferOverflow = true,
            // Without this the provider pads with silence and never reports "empty",
            // so the drain loop below would never end.
            ReadFully = false,
        };

        lock (_gate)
        {
            _samples.Clear();
            _heardSpeech = false;
            _silentSampleCount = 0;
            _autoStopFired = false;
            _stopOnSilence = stopOnSilence;
            _capture = capture;
            _incoming = incoming;
            _resampled = Resampled(incoming);
        }

        capture.DataAvailable += OnDataAvailable;
        capture.StartRecording();
    }

    /// <summary>
    /// Whatever the microphone offers → 16 kHz mono float.
    ///
    /// Deliberately the WDL resampler rather than <c>MediaFoundationResampler</c>:
    /// Media Foundation is COM and wants an MTA thread, but recording is started
    /// and stopped from WPF's STA thread, which crashes it inside ProcessOutput.
    /// WDL is pure managed code and has no apartment to be wrong about.
    /// </summary>
    private static ISampleProvider Resampled(IWaveProvider source)
    {
        var samples = source.ToSampleProvider();
        var mono = samples.WaveFormat.Channels switch
        {
            1 => samples,
            2 => new StereoToMonoSampleProvider(samples) { LeftVolume = 0.5f, RightVolume = 0.5f },
            _ => new MultiplexingSampleProvider([samples], 1),
        };
        return mono.WaveFormat.SampleRate == TargetRate
            ? mono
            : new WdlResamplingSampleProvider(mono, TargetRate);
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs args)
    {
        bool shouldStop;
        lock (_gate)
        {
            if (_incoming is null) return; // stopped while this buffer was in flight
            _incoming.AddSamples(args.Buffer, 0, args.BytesRecorded);
            shouldStop = Drain();
        }
        if (shouldStop) OnAutoStop?.Invoke();
    }

    /// <summary>
    /// Pulls everything the chain can produce right now and measures it. Returns
    /// true the one time the recording should stop itself.
    /// Caller must hold <see cref="_gate"/>.
    /// </summary>
    private bool Drain()
    {
        if (_resampled is null) return false;

        var shouldStop = false;
        int read;
        while ((read = _resampled.Read(_pullBuffer, 0, _pullBuffer.Length)) > 0)
        {
            var sum = 0.0;
            for (var index = 0; index < read; index++) sum += _pullBuffer[index] * _pullBuffer[index];
            var rms = Math.Sqrt(sum / read);

            _samples.AddRange(_pullBuffer.AsSpan(0, read));
            if (rms >= SpeechRms)
            {
                _heardSpeech = true;
                _silentSampleCount = 0;
            }
            else if (_heardSpeech)
            {
                _silentSampleCount += read;
            }

            if (!_autoStopFired
                && RecordingStop.ShouldStop(_stopOnSilence, _heardSpeech,
                                            _silentSampleCount, _samples.Count))
            {
                _autoStopFired = true;
                shouldStop = true;
            }
        }
        return shouldStop;
    }

    /// <summary>
    /// Returns the recording and whether any speech was heard. Skip whisper entirely
    /// when nothing was — it hallucinates ("Thank you.") on silence.
    /// </summary>
    internal (float[] Samples, bool HeardSpeech) Stop()
    {
        WasapiCapture? capture;
        lock (_gate) capture = _capture;
        if (capture is null) return ([], false);

        capture.DataAvailable -= OnDataAvailable;
        capture.StopRecording();

        // StopRecording returns before the capture thread has finished; taking the
        // lock is what waits out a callback still in flight.
        float[] samples;
        bool heardSpeech;
        lock (_gate)
        {
            Drain(); // the tail the capture thread had not pulled yet
            samples = [.. _samples];
            heardSpeech = _heardSpeech;
            _capture = null;
            _incoming = null;
            _resampled = null;
        }

        capture.Dispose();
        return (samples, heardSpeech);
    }

    public void Dispose() => Stop();
}
