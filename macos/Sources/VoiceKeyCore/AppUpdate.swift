import Foundation

/// One downloadable file of a GitHub release.
public struct ReleaseAsset: Equatable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

/// Where the check for a newer VoiceKey has got to.
public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: String)
    case downloading(percent: Int)
    case installing
    case failed(String)
}

/// What a click on the update row asks for.
public enum UpdateAction: Equatable { case none, check, install }

/// The rules around installing a newer VoiceKey from its GitHub releases. Pure —
/// the platform does the fetching, unzipping and restarting; this decides which
/// release counts as newer, which file to take, and what the row says.
public enum AppUpdate {

    /// The tag as a version number: releases are tagged `v1.3.0`.
    public static func number(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Strictly higher, component by component, with missing components read as
    /// zero. A tag that is not a plain number sequence — a nightly, a pre-release —
    /// is never newer: offering to install something we cannot place is worse
    /// than saying nothing.
    public static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let candidate = components(number(tag)), let installed = components(current) else {
            return false
        }
        for index in 0..<max(candidate.count, installed.count) {
            let difference = at(candidate, index) - at(installed, index)
            if difference != 0 { return difference > 0 }
        }
        return false
    }

    /// The release's file for one platform — `VoiceKey-1.3.0-macos-arm64.zip`.
    public static func asset(_ assets: [ReleaseAsset], platform: String) -> ReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip")
                       && $0.name.lowercased().contains(platform.lowercased()) }
    }

    // The Windows core has one more rule here — `RootFolder`, which unwraps a zip
    // packed inside a single directory. A macOS release is a bundle: whatever the
    // zip is shaped like, `Updater` looks for the `.app` and copies that, so the
    // rule has nothing to decide.

    /// The footer row is a notification: it stays out of the way until it has news.
    public static func isVisible(_ status: UpdateStatus) -> Bool {
        switch status {
        case .idle, .upToDate: return false
        default: return true
        }
    }

    public static func label(_ status: UpdateStatus) -> String {
        switch status {
        case .idle: return "Check for updates"
        case .checking: return "Checking for updates…"
        case .upToDate: return "VoiceKey is up to date"
        case .available(let version, _): return "Update to \(version)"
        case .downloading(let percent): return "Downloading… \(percent)%"
        case .installing: return "Installing…"
        case .failed(let reason): return "Update check failed — \(reason)"
        }
    }

    public static func click(_ status: UpdateStatus) -> UpdateAction {
        switch status {
        case .available: return .install
        case .checking, .downloading, .installing: return .none
        case .idle, .upToDate, .failed: return .check
        }
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : nil
    }

    private static func at(_ components: [Int], _ index: Int) -> Int {
        index < components.count ? components[index] : 0
    }
}
