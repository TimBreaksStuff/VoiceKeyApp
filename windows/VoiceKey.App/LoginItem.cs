using System.Security;
using Microsoft.Win32;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// Opening VoiceKey when the user signs in: the per-user Run key, and the veto
/// Task Manager writes beside it. Nothing here is machine-wide, so none of it
/// needs elevation.
/// </summary>
internal static class LoginItem
{
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovedPath =
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string Name = "VoiceKey";

    /// <summary>The quoted path Windows should run — null only if there is no process path.</summary>
    private static string? Command =>
        Environment.ProcessPath is { } executable ? $"\"{executable}\"" : null;

    /// <summary>
    /// What the system will actually do at the next sign-in. An entry pointing
    /// somewhere else — the app has been moved since — is not this copy starting
    /// itself, so it reads as Off and turning it on rewrites the path.
    /// </summary>
    internal static LaunchAtLoginState Read()
    {
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(RunPath);
            if (run?.GetValue(Name) is not string entry) return LaunchAtLoginState.Off;
            if (!entry.Equals(Command, StringComparison.OrdinalIgnoreCase))
                return LaunchAtLoginState.Off;
            return IsVetoed() ? LaunchAtLoginState.Blocked : LaunchAtLoginState.On;
        }
        catch (Exception exception) when (exception is SecurityException
            or UnauthorizedAccessException or IOException)
        {
            Log.Line($"could not read the startup entry: {exception.Message}");
            return LaunchAtLoginState.Off;
        }
    }

    internal static void Set(bool enabled)
    {
        if (Command is not { } command)
        {
            Log.Line("no process path — cannot register for startup");
            return;
        }
        try
        {
            using var run = Registry.CurrentUser.CreateSubKey(RunPath);
            if (!enabled)
            {
                run.DeleteValue(Name, throwOnMissingValue: false);
                Log.Line("startup entry removed");
                return;
            }
            run.SetValue(Name, command);
            ClearVeto();
            Log.Line($"startup entry set to {command}");
        }
        catch (Exception exception) when (exception is SecurityException
            or UnauthorizedAccessException or IOException)
        {
            Log.Line($"could not write the startup entry: {exception.Message}");
        }
    }

    /// <summary>
    /// Task Manager's "Startup apps" switch does not remove the Run value — it
    /// writes a blob beside it here. The format is undocumented, but an odd
    /// first byte has meant "disabled" since it appeared; the alternative to
    /// reading it is a row that says On over an app that never starts.
    /// </summary>
    private static bool IsVetoed()
    {
        using var approved = Registry.CurrentUser.OpenSubKey(ApprovedPath);
        return approved?.GetValue(Name) is byte[] { Length: > 0 } veto && (veto[0] & 1) == 1;
    }

    /// <summary>
    /// Turning startup on has to drop an earlier veto as well. Leaving it would
    /// write the Run value, report On, and still never start — exactly the
    /// silent failure this row exists to make visible.
    /// </summary>
    private static void ClearVeto()
    {
        using var approved = Registry.CurrentUser.OpenSubKey(ApprovedPath, writable: true);
        approved?.DeleteValue(Name, throwOnMissingValue: false);
    }
}
