namespace VoiceKey.App;

/// <summary>
/// Where VoiceKey keeps its files. macOS uses ~/Library/Application Support/VoiceKey;
/// the Windows equivalent is %LOCALAPPDATA%\VoiceKey, with the same file names.
/// </summary>
internal static class Storage
{
    internal static string Root { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VoiceKey");

    internal static string Dictionary => Path.Combine(Root, "dictionary.json");
    internal static string History => Path.Combine(Root, "history.json");
    internal static string Models => Path.Combine(Root, "models");
    internal static string LogFile => Path.Combine(Root, "Logs", "VoiceKey.log");

    /// <summary>Creates every directory the app writes into. Call once at launch.</summary>
    internal static void Prepare()
    {
        Directory.CreateDirectory(Models);
        Directory.CreateDirectory(Path.GetDirectoryName(LogFile)!);
    }
}
