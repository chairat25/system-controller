import Foundation

/// One line of what a session said or did, as shown in the screen saver's terminal-style feed.
public struct TranscriptLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case user, assistant, tool
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// What the end of a Claude Code transcript says about a session.
public struct TranscriptDigest: Sendable, Equatable {
    public static let empty = TranscriptDigest(aiTitle: nil, prompt: nil, activity: [])

    /// The topic Claude gave the conversation, the one the terminal tab shows.
    public let aiTitle: String?
    /// The newest thing the user typed, used as a name until Claude has picked a topic.
    public let prompt: String?
    /// The latest messages and tool calls, oldest first.
    public let activity: [TranscriptLine]

    public var title: String? { aiTitle ?? prompt.map { Self.shorten($0, to: ClaudeTranscript.titleLength) } }

    public init(aiTitle: String?, prompt: String?, activity: [TranscriptLine]) {
        self.aiTitle = aiTitle
        self.prompt = prompt
        self.activity = activity
    }

    static func shorten(_ text: String, to length: Int) -> String {
        text.count <= length ? text : String(text.prefix(length - 1)) + "…"
    }
}

/// Reads the tail of a transcript. The first line of a tail may be cut off, so it is simply skipped when it does not parse.
public enum ClaudeTranscript {
    public static let titleLength = 60
    public static let lineLength = 160
    /// Lines longer than this hold pasted images or huge tool output, never a message worth showing.
    private static let maximumLineBytes = 256 * 1024
    private static let newline = UInt8(ascii: "\n")
    /// Most readable first: a tool's own description beats its raw command.
    private static let toolDetailKeys = ["description", "file_path", "pattern", "url", "query", "prompt", "command"]
    /// Tool calls beyond the newest few are dropped first, so a run of them cannot push a reply off the feed.
    private static let toolLineBudget = 3

    public static func digest(inTail tail: Data, activityLimit: Int = 5) -> TranscriptDigest {
        var aiTitle: String?
        var prompt: String?
        var newestFirst: [TranscriptLine] = []

        for line in tail.split(separator: newline).reversed() where line.count <= maximumLineBytes {
            let isDone = aiTitle != nil && prompt != nil && newestFirst.count >= activityLimit * 3
            if isDone { break }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "ai-title":
                if aiTitle == nil, let title = clean(object["aiTitle"] as? String) { aiTitle = title }
            case "user":
                guard let text = userText(object) else { continue }
                if prompt == nil { prompt = text }
                newestFirst.append(TranscriptLine(kind: .user, text: shorten(text)))
            case "assistant":
                // Blocks of one reply are in reading order, so they are reversed to keep newest first.
                newestFirst.append(contentsOf: assistantLines(object).reversed())
            default:
                continue
            }
        }
        return TranscriptDigest(aiTitle: aiTitle, prompt: prompt,
                                activity: Array(budgeted(newestFirst).prefix(activityLimit).reversed()))
    }

    /// Newest first in, newest first out, with all but the newest few tool calls removed.
    private static func budgeted(_ newestFirst: [TranscriptLine]) -> [TranscriptLine] {
        var toolLines = 0
        return newestFirst.filter { line in
            guard line.kind == .tool else { return true }
            toolLines += 1
            return toolLines <= toolLineBudget
        }
    }

    private static func firstLine(_ text: String?) -> String? {
        text?.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
    }

    /// What the user typed. Nil for tool results, sub-agent chatter and the system text Claude Code injects.
    private static func userText(_ object: [String: Any]) -> String? {
        guard object["isSidechain"] as? Bool != true, object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }
        let raw: String?
        if let text = message["content"] as? String {
            raw = text
        } else if let parts = message["content"] as? [[String: Any]] {
            guard !parts.contains(where: { $0["type"] as? String == "tool_result" }) else { return nil }
            raw = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
        } else {
            raw = nil
        }
        guard let text = clean(raw), !text.hasPrefix("<") else { return nil }
        return text
    }

    private static func assistantLines(_ object: [String: Any]) -> [TranscriptLine] {
        guard object["isSidechain"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            switch block["type"] as? String {
            case "text":
                return clean(block["text"] as? String).map { TranscriptLine(kind: .assistant, text: shorten($0)) }
            case "tool_use":
                guard let name = block["name"] as? String else { return nil }
                let input = block["input"] as? [String: Any] ?? [:]
                let detail = toolDetailKeys.lazy.compactMap { clean(firstLine(input[$0] as? String)) }.first
                return TranscriptLine(kind: .tool, text: shorten([name, detail].compactMap { $0 }.joined(separator: "  ")))
            default:
                return nil
            }
        }
    }

    /// One line of text with runs of whitespace collapsed; nil when nothing is left.
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func shorten(_ text: String) -> String {
        TranscriptDigest.shorten(text, to: lineLength)
    }
}
