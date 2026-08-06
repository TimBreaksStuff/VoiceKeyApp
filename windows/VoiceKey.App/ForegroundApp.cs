using System.Diagnostics;
using System.Runtime.InteropServices;

namespace VoiceKey.App;

/// <summary>
/// Which app the transcript is about to land in. macOS asks NSWorkspace for the
/// frontmost bundle ID; Windows has no such identifier, so the foreground window's
/// process name stands in.
/// </summary>
internal static class ForegroundApp
{
    /// <summary>The foreground app's process name ("Code", "OUTLOOK"), or null.</summary>
    internal static string? ProcessName()
    {
        var window = GetForegroundWindow();
        if (window == nint.Zero) return null;
        _ = GetWindowThreadProcessId(window, out var processId);
        if (processId == 0) return null;
        try
        {
            using var process = Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            return null;
        }
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
}
