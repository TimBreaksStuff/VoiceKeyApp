import Foundation

/// One dictation: what was typed, when, and how long the recording ran.
///
/// The duration is what makes a words-per-minute figure possible; it is 0 when
/// a transcript arrives from somewhere that did not time the recording.
public struct Transcript: Codable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let date: Date
    public let duration: TimeInterval

    public init(id: UUID = UUID(), text: String, date: Date, duration: TimeInterval = 0) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
    }

    public var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// The dictation log, newest first: the status menu lists the newest few, the
/// main window shows all of them grouped by day, and the stats derive from it.
///
/// Persisted to `history.json` next to the dictionary — the window's list and
/// its lifetime stats have to survive a relaunch to mean anything.
public struct TranscriptHistory: Equatable {

    /// How many transcripts the status menu lists.
    private static let menuLimit = 10
    /// Ceiling on what is kept, so the file cannot grow without bound.
    private static let storageLimit = 2_000

    /// Every recorded dictation, newest first.
    public let records: [Transcript]

    public init() {
        self.records = []
    }

    public init(records: [Transcript]) {
        self.records = Array(records.prefix(Self.storageLimit))
    }

    /// The newest transcripts' text, newest first — what the status menu lists.
    public var entries: [String] {
        records.prefix(Self.menuLimit).map(\.text)
    }

    /// Returns a new history with `transcript` prepended.
    ///
    /// Blank transcripts and an immediate repeat of the newest entry are ignored,
    /// and the oldest record is dropped once the storage limit is reached.
    public func adding(_ transcript: String, at date: Date = Date(),
                       duration: TimeInterval = 0) -> TranscriptHistory {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return self }
        guard records.first?.text != transcript else { return self }
        let record = Transcript(text: transcript, date: date, duration: duration)
        return TranscriptHistory(records: [record] + records)
    }

    /// Returns a new history without the given record; unknown ids change nothing.
    public func removing(_ id: Transcript.ID) -> TranscriptHistory {
        TranscriptHistory(records: records.filter { $0.id != id })
    }

    /// Returns a new history with the record put back in date order — what the
    /// undo after a delete calls. A record that is already there changes nothing.
    public func restoring(_ record: Transcript) -> TranscriptHistory {
        guard !records.contains(where: { $0.id == record.id }) else { return self }
        return TranscriptHistory(records: (records + [record]).sorted { $0.date > $1.date })
    }

    /// Returns an empty history — every transcript deleted at once.
    public func cleared() -> TranscriptHistory {
        TranscriptHistory()
    }

    /// True when there is nothing recorded, and so nothing to clear.
    public var isEmpty: Bool { records.isEmpty }

    /// The whole log as plain text, newest first, each transcript under its own
    /// timestamp — what "Export all" writes.
    public func exportText(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return records
            .map { "\(formatter.string(from: $0.date))\n\($0.text)\n" }
            .joined(separator: "\n")
    }

    /// Display-only, single-line rendering of a transcript for a menu item:
    /// whitespace runs collapse to single spaces and anything beyond 60
    /// characters is replaced by an ellipsis.
    public static func menuTitle(for transcript: String) -> String {
        let collapsed = transcript.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > 60 else { return collapsed }
        return String(collapsed.prefix(60)) + "…"
    }

    // MARK: - Storage

    /// Reads the log from disk; nil when the file is missing or malformed — a
    /// broken file must degrade to "no history", never crash the app.
    public static func load(from url: URL) -> TranscriptHistory? {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Transcript].self, from: data)
        else { return nil }
        return TranscriptHistory(records: records)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
    }
}
