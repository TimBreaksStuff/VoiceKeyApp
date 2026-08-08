import Foundation

/// File logger — ~/Library/Logs/VoiceKey.log. The unified log redacts NSLog
/// interpolations as <private>, which makes it useless for diagnostics.
enum Log {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/VoiceKey.log")
    private static let df: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return d
    }()

    private static let maxBytes = 1_000_000

    /// Call once at launch. The log is append-only and would otherwise grow
    /// forever (~300 bytes per dictation); past ~1 MB the oldest half is
    /// dropped, starting at a line boundary so the file never opens mid-line.
    static func trimIfLarge() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? Int, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        let kept = data.suffix(maxBytes / 2)
        let start = kept.firstIndex(of: UInt8(ascii: "\n")).map(kept.index(after:)) ?? kept.startIndex
        try? Data(kept[start...]).write(to: url, options: .atomic)
    }

    static func line(_ msg: String) {
        let s = "\(df.string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(s.utf8))
        } else {
            try? s.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
