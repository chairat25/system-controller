import Foundation

/// Turns what a terminal shows into the lines worth mirroring on the screen saver.
public enum TerminalScreen {
    /// Separators in the text a capture script prints: one record per terminal, `recordSeparator` between its tty and its text.
    public static let unitSeparator: Character = "\u{1F}"
    public static let recordSeparator: Character = "\u{1E}"
    private static let ruleLength = 10

    /// The captures of several terminals printed as `tty ␞ text ␟ tty ␞ text ␟`, keyed by tty.
    public static func parseCaptures(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for record in output.split(separator: unitSeparator) {
            guard let split = record.firstIndex(of: recordSeparator) else { continue }
            let tty = record[..<split].trimmingCharacters(in: .whitespacesAndNewlines)
            result[tty] = String(record[record.index(after: split)...])
        }
        return result
    }

    /// The last `limit` lines of the conversation on screen. Claude Code draws its prompt between two long rules with the
    /// status bar underneath, so everything from the upper rule down is dropped; blank lines are squeezed out.
    public static func conversationTail(_ screen: String, limit: Int) -> [String] {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        let rules = lines.indices.filter { isRule(lines[$0]) }
        let conversation = rules.count >= 2 ? Array(lines[..<rules[rules.count - 2]]) : lines
        let visible = conversation.map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return Array(visible.suffix(limit))
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= ruleLength && trimmed.allSatisfy { $0 == "─" }
    }
}
