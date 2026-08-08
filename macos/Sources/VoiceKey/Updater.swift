import Foundation
import VoiceKeyCore

/// Installs a newer VoiceKey from the project's GitHub releases. The rules —
/// which release is newer, which file to take, what the row says — live in
/// `AppUpdate`; this fetches, unzips, and hands the swap to a script that runs
/// once VoiceKey itself is gone.
enum Updater {

    private static let latestRelease =
        "https://api.github.com/repos/TimBreaksStuff/VoiceKeyApp/releases/latest"

    private static let platform = "macos-arm64"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check() async -> UpdateStatus {
        guard let url = URL(string: latestRelease) else { return .failed("bad release URL") }
        var request = URLRequest(url: url)
        // GitHub rejects a request with no user agent outright.
        request.setValue("VoiceKey/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("GitHub said no")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return .failed("unreadable release")
            }
            Log.line("update check: latest=\(tag) current=\(currentVersion)")
            guard AppUpdate.isNewer(tag, than: currentVersion) else { return .upToDate }

            let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { asset -> ReleaseAsset? in
                guard let name = asset["name"] as? String,
                      let url = asset["browser_download_url"] as? String else { return nil }
                return ReleaseAsset(name: name, url: url)
            }
            guard let download = AppUpdate.asset(assets, platform: platform) else {
                Log.line("update \(tag) has no \(platform) download")
                return .upToDate
            }
            return .available(version: AppUpdate.number(tag), url: download.url)
        } catch {
            Log.line("update check FAILED: \(error.localizedDescription)")
            return .failed("GitHub unreachable")
        }
    }

    /// Downloads the release, unpacks it beside the install, and starts the
    /// script that copies it in. Returns only if that never got far enough to
    /// hand over — on success the caller quits and the script takes it from there.
    static func install(from url: String, onProgress: @escaping (Int) -> Void) async -> UpdateStatus {
        guard let source = URL(string: url) else { return .failed("bad download URL") }
        let staging = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceKey/update")

        do {
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            let zip = staging.appendingPathComponent("VoiceKey.zip")
            try await download(source, to: zip, onProgress: onProgress)

            let unpacked = staging.appendingPathComponent("unpacked")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            guard let app = appBundle(in: unpacked) else { return .failed("no app in the download") }

            let script = try writeSwapScript(from: app)
            Log.line("update staged — \(app.path) → \(Bundle.main.bundleURL.path)")
            try run("/bin/sh", [script.path], wait: false)
            return .installing
        } catch {
            Log.line("update install FAILED: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - The parts

    private static func download(_ url: URL, to path: URL,
                                 onProgress: @escaping (Int) -> Void) async throws {
        var request = URLRequest(url: url)
        request.setValue("VoiceKey/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let progress = DownloadProgress(onProgress: onProgress)
        let (temporary, _) = try await URLSession.shared.download(for: request, delegate: progress)
        try? FileManager.default.removeItem(at: path)
        try FileManager.default.moveItem(at: temporary, to: path)
    }

    /// The `.app` in the download — at the top of the zip, or one folder in.
    private static func appBundle(in directory: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        return items.compactMap { folder -> URL? in
            let nested = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? []
            return nested.first { $0.pathExtension == "app" }
        }.first
    }

    /// The swap cannot happen from inside the bundle being replaced. The script
    /// waits for this process to go, copies the new build over the old one, and
    /// starts it again. The quarantine flag goes with it — the download would
    /// otherwise be blocked by Gatekeeper, as the first install is.
    private static func writeSwapScript(from app: URL) throws -> URL {
        let target = Bundle.main.bundleURL
        let script = app.deletingLastPathComponent().appendingPathComponent("install.sh")
        let body = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 1; done
            rm -rf "\(target.path)"
            cp -R "\(app.path)" "\(target.path)"
            xattr -dr com.apple.quarantine "\(target.path)"
            open "\(target.path)"
            rm -f "$0"

            """
        try body.write(to: script, atomically: true, encoding: .utf8)
        return script
    }

    private static func run(_ tool: String, _ arguments: [String], wait: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        if wait { process.waitUntilExit() }
    }
}

/// Percentages for the row while the zip comes down. A download task reports
/// progress to its delegate; the async `download(for:)` has nowhere else to put it.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Int) -> Void
    private var lastReported = -1

    init(onProgress: @escaping (Int) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
        guard percent != lastReported else { return }
        lastReported = percent
        onProgress(percent)
    }

    /// Required by the protocol; the async form of the request owns the file.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
