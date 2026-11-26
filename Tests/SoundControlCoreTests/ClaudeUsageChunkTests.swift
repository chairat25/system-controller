import Foundation
import Testing
@testable import SoundControlCore

@Suite("Claude usage chunk scanning")
struct ClaudeUsageChunkTests {
    private func assistant(_ id: String, _ stamp: String, output: Int = 1) -> String {
        #"{"type":"assistant","timestamp":"\#(stamp)","message":{"id":"\#(id)","usage":{"output_tokens":\#(output)}}}"#
    }

    private let cutoff = ISO8601DateFormatter().date(from: "2026-11-11T00:00:00Z")!

    @Test("finds every assistant line with usage, in order, and skips the rest")
    func scansLines() {
        let text = [
            #"{"type":"user","timestamp":"2026-11-11T05:00:00Z","message":{"content":"hi"}}"#,
            assistant("a", "2026-11-11T05:00:01Z", output: 3),
            "",
            "not json but mentions \"usage\"",
            assistant("b", "2026-11-11T05:00:02Z", output: 4),
        ].joined(separator: "\n") + "\n"
        let entries = ClaudeUsage.entries(inLines: Data(text.utf8), since: cutoff)
        #expect(entries.map(\.id) == ["a", "b"])
        #expect(entries.map(\.tokens) == [3, 4])
    }

    @Test("drops lines from before the cutoff")
    func dropsOld() {
        let text = assistant("old", "2026-11-10T23:59:59Z") + "\n" + assistant("new", "2026-11-11T00:00:01Z")
        #expect(ClaudeUsage.entries(inLines: Data(text.utf8), since: cutoff).map(\.id) == ["new"])
    }

    @Test("a last line without a newline, and a slice that does not start at index 0, both work")
    func slices() {
        let text = "xx\n" + assistant("a", "2026-11-11T01:00:00Z")
        let data = Data(text.utf8)
        let slice = data[data.index(data.startIndex, offsetBy: 3)...]
        #expect(ClaudeUsage.entries(inLines: slice, since: cutoff).map(\.id) == ["a"])
        #expect(ClaudeUsage.entries(inLines: Data(), since: cutoff).isEmpty)
    }

    @Test("gives the same entries as parsing line by line")
    func matchesLineByLine() {
        let lines = (0..<200).map { assistant("m\($0)", String(format: "2026-11-11T%02d:%02d:00Z", $0 / 60, $0 % 60), output: $0) }
        let data = Data(lines.joined(separator: "\n").utf8)
        let expected = lines.compactMap { ClaudeUsage.entry(fromLine: Data($0.utf8)) }
        #expect(ClaudeUsage.entries(inLines: data, since: cutoff) == expected)
    }
}
