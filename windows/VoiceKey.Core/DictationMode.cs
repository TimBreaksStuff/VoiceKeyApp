namespace VoiceKey.Core;

/// <summary>
/// Per-app dictation mode ("Power Mode"): the foreground app decides how a
/// transcript is punctuated before it is inserted at the cursor.
/// </summary>
public enum DictationMode
{
    /// <summary>Terminals, editors, IDEs — spoken commands should not gain a trailing period.</summary>
    Code,
    /// <summary>Mail clients — sentences should end in punctuation.</summary>
    Email,
    /// <summary>Everything else — the transcript is inserted verbatim.</summary>
    Standard,
}

public static class DictationModes
{
    /// <summary>
    /// Whether a finished transcript should be typed at the cursor at all.
    ///
    /// It should not when VoiceKey itself is frontmost: the cursor is then in
    /// VoiceKey's own window, and pasting there types into the search field —
    /// which filters the library down to the transcript just spoken. The
    /// transcript is in the list either way, so the clipboard is the honest
    /// place for it. An unknown app on either side is assumed to be elsewhere.
    /// </summary>
    public static bool InsertsAtCursor(string? frontmostProcess, string? ownProcess)
    {
        if (frontmostProcess is null || ownProcess is null) return true;
        return !string.Equals(frontmostProcess, ownProcess, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Executable names, matched case-insensitively without their <c>.exe</c> suffix.
    /// macOS keys this table on bundle IDs; Windows has no equivalent stable identifier,
    /// so the executable name stands in.
    /// </summary>
    private static readonly HashSet<string> CodeProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        // terminals
        "windowsterminal", "wt", "cmd", "powershell", "pwsh",
        "alacritty", "wezterm-gui", "conemu64", "hyper",
        // editors and IDEs
        "code", "code - insiders", "cursor", "devenv", "zed",
        "sublime_text", "notepad++", "githubdesktop", "windsurf",
        // JetBrains ships one executable per IDE; macOS matches its bundle IDs by
        // prefix, but "idea"/"pycharm" are too short to prefix-match safely here.
        "idea64", "pycharm64", "webstorm64", "goland64", "rider64",
        "clion64", "phpstorm64", "rubymine64", "datagrip64", "rustrover64",
    };

    private static readonly HashSet<string> EmailProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "outlook", "olk", "hxoutlook", "thunderbird", "mailclient",
    };

    /// <summary>
    /// Mode for the foreground app. Accepts a bare process name, an executable name, or a
    /// full module path — null or unknown maps to <see cref="DictationMode.Standard"/>.
    /// </summary>
    public static DictationMode ForProcess(string? processName)
    {
        var name = Normalised(processName);
        if (name.Length == 0) return DictationMode.Standard;
        if (CodeProcesses.Contains(name)) return DictationMode.Code;
        if (EmailProcesses.Contains(name)) return DictationMode.Email;
        return DictationMode.Standard;
    }

    private static string Normalised(string? processName)
    {
        if (string.IsNullOrWhiteSpace(processName)) return "";
        var name = Path.GetFileName(processName.Trim());
        return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            ? name[..^4]
            : name;
    }

    /// <summary>Mode-specific transcript formatting. Pure.</summary>
    public static string Format(this DictationMode mode, string text) => mode switch
    {
        DictationMode.Code => FormattedForCode(text),
        DictationMode.Email => FormattedForEmail(text),
        _ => text,
    };

    /// <summary>
    /// Drops exactly one trailing period — but leaves "…" and "..." intact, since
    /// those are dictated content rather than sentence punctuation.
    /// </summary>
    private static string FormattedForCode(string text)
    {
        var trimmed = text.TrimEnd();
        if (!trimmed.EndsWith('.')) return trimmed;
        var withoutPeriod = trimmed[..^1];
        return withoutPeriod.EndsWith('.') ? trimmed : withoutPeriod;
    }

    /// <summary>
    /// Appends a period when the sentence trails off on a letter or digit;
    /// anything already ending in punctuation (. ! ? : …) is left alone.
    /// </summary>
    private static string FormattedForEmail(string text)
    {
        var trimmed = text.TrimEnd();
        if (trimmed.Length == 0) return trimmed;
        var last = trimmed[^1];
        return char.IsLetter(last) || char.IsNumber(last) ? trimmed + "." : trimmed;
    }
}
