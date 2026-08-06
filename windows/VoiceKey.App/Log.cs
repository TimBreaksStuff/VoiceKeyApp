using System.Globalization;

namespace VoiceKey.App;

/// <summary>
/// File logger — %LOCALAPPDATA%\VoiceKey\Logs\VoiceKey.log. Every hotkey event,
/// permission state and transcript goes here; when a change "doesn't work", this
/// file is the first place to look.
/// </summary>
internal static class Log
{
    private const int MaxBytes = 1_000_000;
    private static readonly Lock Gate = new();

    /// <summary>
    /// Call once at launch. The log is append-only and would otherwise grow
    /// forever (~300 bytes per dictation); past ~1 MB the oldest half is
    /// dropped, starting at a line boundary so the file never opens mid-line.
    /// </summary>
    internal static void TrimIfLarge()
    {
        try
        {
            var file = new FileInfo(Storage.LogFile);
            if (!file.Exists || file.Length <= MaxBytes) return;

            var kept = File.ReadAllBytes(Storage.LogFile)[^(MaxBytes / 2)..];
            var newline = Array.IndexOf(kept, (byte)'\n');
            File.WriteAllBytes(Storage.LogFile, newline < 0 ? kept : kept[(newline + 1)..]);
        }
        catch (IOException) { /* diagnostics must never take the app down */ }
        catch (UnauthorizedAccessException) { }
    }

    internal static void Line(string message)
    {
        var stamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture);
        try
        {
            lock (Gate) File.AppendAllText(Storage.LogFile, $"{stamp} {message}{Environment.NewLine}");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
