namespace VoiceKey.Core;

/// <summary>One downloadable file of a GitHub release.</summary>
public sealed record ReleaseAsset(string Name, string Url);

/// <summary>Where the check for a newer VoiceKey has got to.</summary>
public abstract record UpdateStatus
{
    private UpdateStatus() { }

    public sealed record IdleState : UpdateStatus;
    public sealed record CheckingState : UpdateStatus;
    public sealed record UpToDateState : UpdateStatus;
    public sealed record AvailableState(string Version, string Url) : UpdateStatus;
    public sealed record DownloadingState(int Percent) : UpdateStatus;
    public sealed record InstallingState : UpdateStatus;
    public sealed record FailedState(string Reason) : UpdateStatus;

    public static readonly UpdateStatus Idle = new IdleState();
    public static readonly UpdateStatus Checking = new CheckingState();
    public static readonly UpdateStatus UpToDate = new UpToDateState();
    public static readonly UpdateStatus Installing = new InstallingState();

    public static UpdateStatus Available(string version, string url) => new AvailableState(version, url);
    public static UpdateStatus Downloading(int percent) => new DownloadingState(percent);
    public static UpdateStatus Failed(string reason) => new FailedState(reason);
}

/// <summary>What a click on the update row asks for.</summary>
public enum UpdateAction { None, Check, Install }

/// <summary>
/// The rules around installing a newer VoiceKey from its GitHub releases. Pure —
/// the platform does the fetching, unzipping and restarting; this decides which
/// release counts as newer, which file to take, and what the row says.
/// </summary>
public static class AppUpdate
{
    /// <summary>The tag as a version number: releases are tagged `v1.3.0`.</summary>
    public static string Number(string tag) => tag.StartsWith('v') ? tag[1..] : tag;

    /// <summary>
    /// Strictly higher, component by component, with missing components read as
    /// zero. A tag that is not a plain number sequence — a nightly, a pre-release —
    /// is never newer: offering to install something we cannot place is worse
    /// than saying nothing.
    /// </summary>
    public static bool IsNewer(string tag, string current)
    {
        var candidate = Components(Number(tag));
        var installed = Components(current);
        if (candidate is null || installed is null) return false;

        for (var index = 0; index < Math.Max(candidate.Count, installed.Count); index++)
        {
            var difference = At(candidate, index) - At(installed, index);
            if (difference != 0) return difference > 0;
        }
        return false;
    }

    /// <summary>The release's file for one platform — `VoiceKey-1.3.0-win-x64.zip`.</summary>
    public static ReleaseAsset? Asset(IReadOnlyList<ReleaseAsset> assets, string platform) =>
        assets.FirstOrDefault(asset => asset.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
                                       && asset.Name.Contains(platform, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// The single folder every entry of the zip sits in, if there is one — that
    /// is the build, and copying the wrapper itself would nest it a level deeper.
    /// </summary>
    public static string? RootFolder(IReadOnlyList<string> entries)
    {
        if (entries.Count == 0) return null;
        var first = entries[0].Split('/', '\\')[0];
        if (first == entries[0]) return null; // a loose file at the top: no wrapper
        return entries.All(entry => entry.Split('/', '\\')[0] == first) ? first : null;
    }

    /// <summary>The footer row is a notification: it stays out of the way until it has news.</summary>
    public static bool IsVisible(UpdateStatus status) =>
        status is not (UpdateStatus.IdleState or UpdateStatus.UpToDateState);

    public static string Label(UpdateStatus status) => status switch
    {
        UpdateStatus.IdleState => "Check for updates",
        UpdateStatus.CheckingState => "Checking for updates…",
        UpdateStatus.UpToDateState => "VoiceKey is up to date",
        UpdateStatus.AvailableState available => $"Update to {available.Version}",
        UpdateStatus.DownloadingState downloading => $"Downloading… {downloading.Percent}%",
        UpdateStatus.InstallingState => "Installing…",
        UpdateStatus.FailedState failed => $"Update check failed — {failed.Reason}",
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    public static UpdateAction Click(UpdateStatus status) => status switch
    {
        UpdateStatus.AvailableState => UpdateAction.Install,
        UpdateStatus.CheckingState or UpdateStatus.DownloadingState
            or UpdateStatus.InstallingState => UpdateAction.None,
        _ => UpdateAction.Check,
    };

    private static IReadOnlyList<int>? Components(string version)
    {
        var parts = version.Split('.');
        if (parts.Length == 0 || parts.Any(part => !int.TryParse(part, out _))) return null;
        return parts.Select(int.Parse).ToList();
    }

    private static int At(IReadOnlyList<int> components, int index) =>
        index < components.Count ? components[index] : 0;
}
