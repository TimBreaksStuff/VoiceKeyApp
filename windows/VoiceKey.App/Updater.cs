using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using VoiceKey.Core;

namespace VoiceKey.App;

/// <summary>
/// Installs a newer VoiceKey from the project's GitHub releases. The rules —
/// which release is newer, which file to take, what the row says — live in
/// <see cref="AppUpdate"/>; this fetches, unzips, and hands the swap to a script
/// that runs once VoiceKey itself is gone.
/// </summary>
internal sealed class Updater
{
    private const string LatestRelease =
        "https://api.github.com/repos/TimBreaksStuff/VoiceKeyApp/releases/latest";

    private const string Platform = "win-x64";

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(10) };

    internal static string CurrentVersion =>
        Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                .Split('+')[0]
        ?? "0.0.0";

    internal async Task<UpdateStatus> CheckAsync()
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, LatestRelease);
            // GitHub rejects a request with no user agent outright.
            request.Headers.Add("User-Agent", $"VoiceKey/{CurrentVersion}");
            request.Headers.Add("Accept", "application/vnd.github+json");

            using var response = await Http.SendAsync(request);
            response.EnsureSuccessStatusCode();
            using var release = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

            var tag = release.RootElement.GetProperty("tag_name").GetString() ?? "";
            Log.Line($"update check: latest={tag} current={CurrentVersion}");
            if (!AppUpdate.IsNewer(tag, CurrentVersion)) return UpdateStatus.UpToDate;

            var assets = release.RootElement.GetProperty("assets").EnumerateArray()
                .Select(asset => new ReleaseAsset(asset.GetProperty("name").GetString() ?? "",
                                                  asset.GetProperty("browser_download_url").GetString() ?? ""))
                .ToList();
            var download = AppUpdate.Asset(assets, Platform);
            if (download is null)
            {
                Log.Line($"update {tag} has no {Platform} download");
                return UpdateStatus.UpToDate;
            }

            return UpdateStatus.Available(AppUpdate.Number(tag), download.Url);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException
            or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            Log.Line($"update check FAILED: {exception.Message}");
            return UpdateStatus.Failed(Reason(exception));
        }
    }

    /// <summary>
    /// Downloads the release, unpacks it beside the install, and starts the
    /// script that copies it in. Returns only if that never got far enough to
    /// hand over — on success the caller quits and the script takes it from there.
    /// </summary>
    internal async Task<UpdateStatus> InstallAsync(string url, Action<int> onProgress)
    {
        var staging = Path.Combine(Storage.Root, "update");
        try
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
            Directory.CreateDirectory(staging);

            var zip = Path.Combine(staging, "VoiceKey.zip");
            await DownloadAsync(url, zip, onProgress);

            var unpacked = Path.Combine(staging, "unpacked");
            List<string> entries;
            using (var archive = ZipFile.OpenRead(zip))
            {
                entries = archive.Entries.Select(entry => entry.FullName).ToList();
            }
            ZipFile.ExtractToDirectory(zip, unpacked);
            var source = AppUpdate.RootFolder(entries) is { } folder
                ? Path.Combine(unpacked, folder)
                : unpacked;

            var script = WriteSwapScript(source);
            Log.Line($"update staged — {source} → {AppContext.BaseDirectory}");
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
            });
            return UpdateStatus.Installing;
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException
            or IOException or UnauthorizedAccessException or InvalidDataException)
        {
            Log.Line($"update install FAILED: {exception}");
            return UpdateStatus.Failed(Reason(exception));
        }
    }

    private static async Task DownloadAsync(string url, string path, Action<int> onProgress)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Add("User-Agent", $"VoiceKey/{CurrentVersion}");

        using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        var total = response.Content.Headers.ContentLength ?? 0;
        using var source = await response.Content.ReadAsStreamAsync();
        using var file = File.Create(path);

        var buffer = new byte[81920];
        long written = 0;
        var lastReported = -1;
        int read;
        while ((read = await source.ReadAsync(buffer)) > 0)
        {
            await file.WriteAsync(buffer.AsMemory(0, read));
            written += read;
            if (total <= 0) continue;
            var percent = (int)(written * 100 / total);
            if (percent == lastReported) continue;
            lastReported = percent;
            onProgress(percent);
        }
    }

    /// <summary>
    /// The swap cannot happen from inside the process being replaced. The script
    /// waits for this PID to go, copies the new build over the old one, and
    /// starts it again.
    /// </summary>
    private static string WriteSwapScript(string source)
    {
        var path = Path.Combine(Storage.Root, "update", "install.cmd");
        var target = AppContext.BaseDirectory.TrimEnd('\\');
        var executable = Path.Combine(target, "VoiceKey.exe");

        File.WriteAllText(path, $"""
            @echo off
            :wait
            tasklist /FI "PID eq {Environment.ProcessId}" | find "{Environment.ProcessId}" >nul
            if not errorlevel 1 (
                timeout /t 1 /nobreak >nul
                goto wait
            )
            robocopy "{source}" "{target}" /E /NFL /NDL /NJH /NJS /NP >nul
            start "" "{executable}"
            del "%~f0"
            """);
        return path;
    }

    private static string Reason(Exception exception) => exception switch
    {
        HttpRequestException => "GitHub unreachable",
        TaskCanceledException => "timed out",
        _ => exception.Message,
    };
}
