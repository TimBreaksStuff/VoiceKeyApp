import Foundation

/// The main window's transcript list: the days that have something in them, each
/// with its rows, after the search box and the sort control have had their say.
/// Pure — the view only draws what this returns.
public struct TranscriptList: Equatable {

    /// How the library is ordered — the "Newest first ▾" control in the list header.
    public enum Sort: Equatable { case newest, oldest, longest }

    public struct Row: Equatable {
        public let id: Transcript.ID
        public let time: String
        public let text: String
        /// "12 words" — the row's own word count.
        public let words: String
    }

    public struct Group: Equatable {
        /// "Today", "Yesterday", or the day ("Sun 2 August").
        public let label: String
        /// "14 transcripts · 2,140 words".
        public let meta: String
        public let rows: [Row]
    }

    public let groups: [Group]

    /// True when there is nothing to draw — no history, or nothing matched.
    public var isEmpty: Bool { groups.isEmpty }

    public static func make(from records: [Transcript], now: Date = Date(),
                            calendar: Calendar = .current,
                            query: String = "", sort: Sort = .newest) -> TranscriptList {
        let today = calendar.startOfDay(for: now)
        let matching = records.filter { matches($0, query: query) }
        let byDay = Dictionary(grouping: matching) { calendar.startOfDay(for: $0.date) }

        let oldestFirst = sort == .oldest
        let days = byDay.keys.sorted { oldestFirst ? $0 < $1 : $0 > $1 }

        return TranscriptList(groups: days.map { day in
            let ofDay = (byDay[day] ?? []).sorted { ordered($0, before: $1, by: sort) }
            return Group(label: label(for: day, today: today, calendar: calendar),
                         meta: meta(for: ofDay),
                         rows: ofDay.map { row(for: $0, calendar: calendar) })
        })
    }

    /// The status bar's left half: how much is held, and the reassurance that goes
    /// with it. Fixed copy — the privacy claim is the point of the line.
    public static func storageLine(count: Int) -> String {
        "\(counted(count, "transcript")) stored on this machine · nothing is uploaded"
    }

    // MARK: - Filtering and ordering

    private static func matches(_ record: Transcript, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return record.text.range(of: needle, options: .caseInsensitive) != nil
    }

    /// Longest-first still falls back to newest-first, so two transcripts of the
    /// same length keep the order the user watched them arrive in.
    private static func ordered(_ left: Transcript, before right: Transcript, by sort: Sort) -> Bool {
        switch sort {
        case .newest: return left.date > right.date
        case .oldest: return left.date < right.date
        case .longest:
            guard left.wordCount == right.wordCount else { return left.wordCount > right.wordCount }
            return left.date > right.date
        }
    }

    // MARK: - Rendering

    private static func row(for record: Transcript, calendar: Calendar) -> Row {
        Row(id: record.id,
            time: formatter("hh:mm a", calendar: calendar).string(from: record.date),
            text: record.text,
            words: counted(record.wordCount, "word"))
    }

    private static func label(for day: Date, today: Date, calendar: Calendar) -> String {
        switch calendar.dateComponents([.day], from: day, to: today).day {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: break
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
        return formatter(sameYear ? "EEE d MMMM" : "EEE d MMMM yyyy", calendar: calendar)
            .string(from: day)
    }

    private static func meta(for records: [Transcript]) -> String {
        let words = records.reduce(0) { $0 + $1.wordCount }
        return "\(counted(records.count, "transcript")) · \(counted(words, "word"))"
    }

    private static func counted(_ amount: Int, _ noun: String) -> String {
        "\(TranscriptStats.grouped(amount)) \(noun)\(amount == 1 ? "" : "s")"
    }

    /// Fixed English formats: the numerals and day names are part of the
    /// window's design, not something to re-localise per machine.
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
