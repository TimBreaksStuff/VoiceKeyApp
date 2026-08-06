namespace VoiceKey.Core;

/// <summary>What the system reports about opening VoiceKey when the user signs in.</summary>
public enum LaunchAtLoginState
{
    On,
    Off,
    /// <summary>Registered, but switched off in the system's own startup list.</summary>
    Blocked,
}

/// <summary>What a click on the sidebar's launch-at-login row asks for.</summary>
public enum LaunchAtLoginAction { Enable, Disable, OpenSettings }

/// <summary>
/// The sidebar row that opens VoiceKey at login. Pure — the platform reads the
/// state from the system and carries the action out; this decides what the row
/// says and what clicking it means.
/// </summary>
public static class LaunchAtLogin
{
    /// <param name="title">The platform's own wording — "Start with Windows".</param>
    public static string Label(string title, LaunchAtLoginState state) =>
        $"{title} — {Word(state)}";

    /// <summary>
    /// Blocked asks for the system's list rather than a registration it already
    /// has: registering again would change nothing and read as a dead row.
    /// </summary>
    public static LaunchAtLoginAction Click(LaunchAtLoginState state) => state switch
    {
        LaunchAtLoginState.On => LaunchAtLoginAction.Disable,
        LaunchAtLoginState.Off => LaunchAtLoginAction.Enable,
        _ => LaunchAtLoginAction.OpenSettings,
    };

    private static string Word(LaunchAtLoginState state) => state switch
    {
        LaunchAtLoginState.On => "On",
        LaunchAtLoginState.Off => "Off",
        _ => "Blocked",
    };
}
