using System.Text.Json;
using System.Windows.Input;

namespace VoiceKey.App;

/// <summary>
/// The dictation hotkey, as <c>RegisterHotKey</c> wants it plus the label the menu
/// shows. Persisted so a chosen shortcut survives a restart.
/// </summary>
internal sealed record Shortcut(uint VirtualKey, uint Modifiers, string Label)
{
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModWin = 0x0008;

    /// <summary>Ctrl+Alt+D — ⌃⌥D key for key, which is what macOS uses.</summary>
    internal static Shortcut Default { get; } = new(0x44, ModControl | ModAlt, "Ctrl+Alt+D");

    /// <summary>
    /// The combo just pressed, or null when it is not usable as a global hotkey:
    /// a modifier on its own, or nothing but Shift — plain typing would otherwise
    /// start dictating.
    /// </summary>
    internal static Shortcut? From(Key key, ModifierKeys pressed)
    {
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
            or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin
            or Key.System or Key.None) return null;

        var modifiers = 0u;
        if (pressed.HasFlag(ModifierKeys.Control)) modifiers |= ModControl;
        if (pressed.HasFlag(ModifierKeys.Alt)) modifiers |= ModAlt;
        if (pressed.HasFlag(ModifierKeys.Shift)) modifiers |= ModShift;
        if (pressed.HasFlag(ModifierKeys.Windows)) modifiers |= ModWin;
        if ((modifiers & ~ModShift) == 0) return null;

        return new Shortcut((uint)KeyInterop.VirtualKeyFromKey(key), modifiers,
                            Describe(key, modifiers));
    }

    private static string Describe(Key key, uint modifiers)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0) parts.Add("Ctrl");
        if ((modifiers & ModAlt) != 0) parts.Add("Alt");
        if ((modifiers & ModShift) != 0) parts.Add("Shift");
        if ((modifiers & ModWin) != 0) parts.Add("Win");
        parts.Add(KeyName(key));
        return string.Join("+", parts);
    }

    private static string KeyName(Key key) => key switch
    {
        >= Key.D0 and <= Key.D9 => ((int)(key - Key.D0)).ToString(),
        Key.Return => "Enter",
        Key.Oem3 => "`",
        _ => key.ToString(),
    };

    // MARK: - Persistence

    private static string Path => System.IO.Path.Combine(Storage.Root, "shortcut.json");

    /// <summary>The saved shortcut, or the default when nothing is saved or the file is broken.</summary>
    internal static Shortcut Load()
    {
        try
        {
            return JsonSerializer.Deserialize<Shortcut>(File.ReadAllText(Path)) ?? Default;
        }
        catch (Exception exception) when (exception is IOException or JsonException
            or UnauthorizedAccessException)
        {
            return Default;
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
            Log.Line($"could not save shortcut: {exception.Message}");
        }
    }
}
