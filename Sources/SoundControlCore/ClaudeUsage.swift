import Foundation

/// One Claude reply as recorded in a Claude Code transcript.
public struct TokenUsageEntry: Sendable, Equatable {
    public let id: String
    public let date: Date
    public let tokens: Int

    public init(id: String, date: Date, tokens: Int) {
        self.id = id
        self.date = date
        self.tokens = tokens
    }
}

/// What the screen saver shows about Claude usage.
public struct ClaudeUsageSummary: Sendable, Equatable {
    public static let empty = ClaudeUsageSummary(todayTokens: 0, todayReplies: 0, windowTokens: 0,
                                                 windowReplies: 0, windowResetsAt: nil)

    public let todayTokens: Int
    public let todayReplies: Int
    /// Tokens in the current 5-hour usage window, 0 when no window is open.
    public let windowTokens: Int
    public let windowReplies: Int
    public let windowResetsAt: Date?

    public init(todayTokens: Int, todayReplies: Int, windowTokens: Int, windowReplies: Int, windowResetsAt: Date?) {
        self.todayTokens = todayTokens
        self.todayReplies = todayReplies
        self.windowTokens = windowTokens
        self.windowReplies = windowReplies
        self.windowResetsAt = windowResetsAt
    }

    /// Compact token count: 950, 12.3K, 4.6M.
    public static func format(tokens: Int) -> String {
        switch tokens {
        case ..<1_000: "\(tokens)"
        case ..<1_000_000: String(format: "%.1fK", Double(tokens) / 1_000)
        default: String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }
}

/// Reads Claude Code transcript lines and sums them. Pure, so the scanning code around it stays thin.
public enum ClaudeUsage {
    /// Claude's usage limits reset in blocks of five hours that start on the hour of the first reply.
    public static let windowLength: TimeInterval = 5 * 3600

    /// The reply a transcript line records, or nil for every other line (user turns, tool results, no usage).
    /// Counts input, output and cache-write tokens. Cache reads are left out because they are re-reads, not new work.
    public static func entry(fromLine line: Data) -> TokenUsageEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let date = parse(stamp)
        else { return nil }
        let keys = ["input_tokens", "output_tokens", "cache_creation_input_tokens"]
        let tokens = keys.reduce(0) { $0 + max(usage[$1] as? Int ?? 0, 0) }
        return TokenUsageEntry(id: id, date: date, tokens: tokens)
    }

    public static func summary(of entries: [TokenUsageEntry], now: Date,
                               calendar: Calendar = .current) -> ClaudeUsageSummary {
        let sorted = entries.filter { $0.date <= now }.sorted { $0.date < $1.date }
        let today = sorted.filter { calendar.isDate($0.date, inSameDayAs: now) }
        guard let window = currentWindow(of: sorted, now: now, calendar: calendar) else {
            return ClaudeUsageSummary(todayTokens: total(today), todayReplies: today.count, windowTokens: 0,
                                      windowReplies: 0, windowResetsAt: nil)
        }
        return ClaudeUsageSummary(todayTokens: total(today), todayReplies: today.count,
                                  windowTokens: total(window.entries), windowReplies: window.entries.count,
                                  windowResetsAt: window.end)
    }

    private struct Window {
        var start: Date
        var entries: [TokenUsageEntry]
        var end: Date { start.addingTimeInterval(ClaudeUsage.windowLength) }
    }

    /// Walks replies in order, opening a new window whenever one lands after the previous window ended.
    private static func currentWindow(of sorted: [TokenUsageEntry], now: Date, calendar: Calendar) -> Window? {
        var current: Window?
        for entry in sorted {
            if var open = current, entry.date < open.end {
                open.entries.append(entry)
                current = open
            } else {
                let hour = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                current = Window(start: hour, entries: [entry])
            }
        }
        guard let last = current, now < last.end else { return nil }
        return last
    }

    private static func total(_ entries: [TokenUsageEntry]) -> Int {
        entries.reduce(0) { $0 + $1.tokens }
    }

    static func parse(_ stamp: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(stamp)) ?? (try? Date.ISO8601FormatStyle().parse(stamp))
    }
}
