using System.Text;
using Whisper.net;
using Whisper.net.Ggml;
using Whisper.net.LibraryLoader;

namespace VoiceKey.App;

/// <summary>
/// Whisper.net wrapper — whisper.cpp on the GPU. Switching to a multilingual model
/// means changing <see cref="ModelType"/> to e.g. <c>GgmlType.LargeV3Turbo</c> and
/// clearing <see cref="Language"/> for auto-detection.
/// </summary>
internal sealed class Transcriber : IDisposable
{
    internal const string ModelName = "ggml-small.en";
    private const GgmlType ModelType = GgmlType.SmallEn;
    private const string Language = "en";

    private WhisperFactory? _factory;

    private static string ModelPath => Path.Combine(Storage.Models, ModelName + ".bin");

    /// <summary>
    /// Call once at app launch. The first run downloads the model (~470 MB) into
    /// %LOCALAPPDATA%\VoiceKey\models and reuses it forever after.
    /// </summary>
    internal async Task LoadAsync(CancellationToken token = default)
    {
        // Whisper.net walks this list and keeps the first library it can actually
        // load. CUDA is fastest but its native side needs the CUDA 13 redistributable
        // (cublas64_13.dll) installed system-wide; Vulkan needs nothing beyond the
        // GPU driver, so it is what an untouched machine with a GPU ends up using.
        // The CPU entry is the floor, not the plan.
        RuntimeOptions.RuntimeLibraryOrder =
            [RuntimeLibrary.Cuda, RuntimeLibrary.Vulkan, RuntimeLibrary.Cpu];

        if (!File.Exists(ModelPath)) await DownloadModelAsync(token);

        _factory = WhisperFactory.FromPath(ModelPath);
        Log.Line($"model {ModelName} loaded on {RuntimeOptions.LoadedLibrary?.ToString() ?? "?"}");
    }

    private static async Task DownloadModelAsync(CancellationToken token)
    {
        Log.Line($"downloading model {ModelName}");
        var partial = ModelPath + ".part";
        await using (var source = await WhisperGgmlDownloader.Default
                         .GetGgmlModelAsync(ModelType, cancellationToken: token))
        await using (var destination = File.Create(partial))
        {
            await source.CopyToAsync(destination, token);
        }
        // Rename only once the bytes are all there, so an interrupted download
        // cannot leave a truncated model that loads and then fails.
        File.Move(partial, ModelPath, overwrite: true);
        Log.Line("model download complete");
    }

    /// <summary>
    /// <paramref name="vocabularyPrompt"/> biases recognition toward the user's
    /// vocabulary: whisper takes it as decoder conditioning, so unusual names and
    /// jargon come out spelled the way the dictionary lists them.
    /// </summary>
    internal async Task<string> TranscribeAsync(float[] samples, string? vocabularyPrompt = null,
                                                CancellationToken token = default)
    {
        if (_factory is null) throw new InvalidOperationException("model not loaded");

        var builder = _factory.CreateBuilder().WithLanguage(Language);
        if (!string.IsNullOrWhiteSpace(vocabularyPrompt)) builder = builder.WithPrompt(vocabularyPrompt);

        await using var processor = builder.Build();
        var text = new StringBuilder();
        await foreach (var segment in processor.ProcessAsync(samples, token))
            text.Append(segment.Text);
        return text.ToString().Trim();
    }

    public void Dispose() => _factory?.Dispose();
}
