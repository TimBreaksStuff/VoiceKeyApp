using System.Text.Json;

namespace VoiceKey.App;

/// <summary>
/// The handful of window choices that have to survive a restart. Separate from
/// <see cref="Shortcut"/>, which is the hotkey itself and nothing else.
/// </summary>
internal sealed record Preferences(bool OnboardingDismissed = false)
{
    private static string Path => System.IO.Path.Combine(Storage.Root, "preferences.json");

    /// <summary>What is saved, or the defaults when nothing is saved or the file is broken.</summary>
    internal static Preferences Load()
    {
        try
        {
            return JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path)) ?? new Preferences();
        }
        catch (Exception exception) when (exception is IOException or JsonException
            or UnauthorizedAccessException)
        {
            return new Preferences();
        }
    }

    internal void Save()
    {
        try
        {
            File.WriteAllText(Path, JsonSerializer.Serialize(this));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Log.Line($"could not save preferences: {exception.Message}");
        }
    }
}
