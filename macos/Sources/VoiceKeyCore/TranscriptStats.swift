import Foundation

/// The sidebar's "This week" card, derived from local history alone: what was
/// dictated since Monday, how fast it was spoken, and what that saved.
///
/// Every figure is a finished string — a week with nothing in it still shows a
/// card, with an em dash where there is no honest number to give.
public struct TranscriptStats: Equatable {
    /// "1,284" — words dictated this week.
    public let words: String
    /// "127 wpm", or "—" when no run was timed.
    public let pace: String
    /// "≈18 min", "<1 min", or "—".
    public let typingSaved: String

    /// The typing speed the saving is measured against — a middling office typist,
    /// deliberately conservative, so the number is never flattering by accident.
    private static let typedWordsPerMinute = 40.0

    private static let unknown = "—"

    public static func make(from records: [Transcript], now: Date = Date(),
                            calendar: Calendar = .current) -> TranscriptStats {
        let start = weekStart(of: now, calendar: calendar)
        let thisWeek = records.filter { weekStart(of: $0.date, calendar: calendar) == start }
        let timed = thisWeek.filter { $0.duration > 0 }

        return TranscriptStats(words: grouped(thisWeek.reduce(0) { $0 + $1.wordCount }),
                               pace: medianPace(timed),
                               typingSaved: savedLabel(timed))
    }

    /// Weeks start on Monday, so "this week" means the same thing on every machine
    /// and matches what the Windows build counts.
    private static func weekStart(of date: Date, calendar: Calendar) -> Date {
        var mondays = calendar
        mondays.firstWeekday = 2
        return mondays.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// "2140" → "2,140". Fixed separator: the design's numerals are part of its
    /// look, not something to localise.
    public static func grouped(_ count: Int) -> String {
        let digits = Array(String(abs(count)))
        let chunked = stride(from: digits.count, to: 0, by: -3)
            .map { end in String(digits[max(0, end - 3)..<end]) }
            .reversed()
            .joined(separator: ",")
        return (count < 0 ? "-" : "") + chunked
    }

    // MARK: - Pace

    /// The median rather than the mean, so one odd run does not skew it.
    private static func medianPace(_ timed: [Transcript]) -> String {
        let rates = timed.map { Double($0.wordCount) / ($0.duration / 60) }.sorted()
        guard !rates.isEmpty else { return unknown }
        let middle = rates.count / 2
        let median = rates.count.isMultiple(of: 2)
            ? (rates[middle - 1] + rates[middle]) / 2
            : rates[middle]
        return "\(Int(median.rounded())) wpm"
    }

    // MARK: - Typing saved

    /// How long those words would have taken to type, less the time actually spent
    /// speaking them. Only timed runs count — an untimed one has no speaking time
    /// to subtract, and counting it would inflate the saving.
    private static func savedLabel(_ timed: [Transcript]) -> String {
        guard !timed.isEmpty else { return unknown }
        let typing = Double(timed.reduce(0) { $0 + $1.wordCount }) / typedWordsPerMinute
        let speaking = timed.reduce(0.0) { $0 + $1.duration / 60 }
        let saved = (typing - speaking).rounded()
        return saved < 1 ? "<1 min" : "≈\(grouped(Int(saved))) min"
    }
}
