import Foundation

/// One running Claude Code CLI session, read from `~/.claude/sessions/<pid>.json`.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let pid: Int32
    public let name: String
    public let cwd: String
    /// True while Claude is in the middle of a turn. Idle, waiting on a background shell and the like are not working.
    public let isWorking: Bool
    public let statusUpdatedAt: Date
    /// The topic Claude gave the conversation, the one the terminal tab shows. Nil until a transcript is read.
    public let title: String?

    /// What to call the session on screen: its topic when known, otherwise the short generated name.
    public var displayName: String { title ?? name }

    public init(id: String, pid: Int32, name: String, cwd: String, isWorking: Bool, statusUpdatedAt: Date,
                title: String? = nil) {
        self.title = title
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.isWorking = isWorking
        self.statusUpdatedAt = statusUpdatedAt
    }

    public func withTitle(_ title: String?) -> Self {
        Self(id: id, pid: pid, name: name, cwd: cwd, isWorking: isWorking, statusUpdatedAt: statusUpdatedAt, title: title)
    }

    /// True while the session works, and for `grace` seconds after its status last changed. A reply is written
    /// to the transcript around the moment the session stops, so that is when it must be read closely.
    public func isActive(now: Date, grace: TimeInterval) -> Bool {
        isWorking || now.timeIntervalSince(statusUpdatedAt) < grace
    }

    /// One session per conversation. The same conversation can run in two terminals at once (`claude --resume`),
    /// and a stale copy would otherwise show up as a second session. The copy that is working wins, then the newest.
    public static func collapsed(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        let byID = Dictionary(grouping: sessions, by: \.id)
        return byID.values.compactMap { copies in
            copies.max { ($0.isWorking ? 1 : 0, $0.statusUpdatedAt) < ($1.isWorking ? 1 : 0, $1.statusUpdatedAt) }
        }
    }

    /// Nil for files that are not an interactive session or that lack a pid or session id.
    public static func parse(_ data: Data) -> ClaudeSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, pid > 0,
              let id = object["sessionId"] as? String, !id.isEmpty
        else { return nil }
        if let kind = object["kind"] as? String, kind != "interactive" { return nil }
        let cwd = object["cwd"] as? String ?? ""
        let named = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let name = named ?? URL(fileURLWithPath: cwd).lastPathComponent
        let millis = (object["statusUpdatedAt"] as? Double) ?? 0
        return ClaudeSession(id: id, pid: Int32(pid), name: name.isEmpty ? String(id.prefix(8)) : name, cwd: cwd,
                             isWorking: object["status"] as? String == "busy",
                             statusUpdatedAt: Date(timeIntervalSince1970: millis / 1000))
    }
}

/// What the screen saver lists: sessions that are working, ones that stopped a moment ago, and pinned ones.
public struct ClaudeSessionBoard: Sendable, Equatable {
    public static let empty = ClaudeSessionBoard(sessions: [], lastWorking: [:])
    /// How long a stopped session stays on screen before it fades out.
    public static let lingerSeconds: TimeInterval = 15

    public struct Row: Sendable, Equatable, Identifiable {
        public let session: ClaudeSession
        public let isPinned: Bool
        public var id: String { session.id }
    }

    public let sessions: [ClaudeSession]
    private let lastWorking: [String: Date]

    private init(sessions: [ClaudeSession], lastWorking: [String: Date]) {
        self.sessions = sessions
        self.lastWorking = lastWorking
    }

    /// A new board for the latest scan. Sessions that closed are forgotten.
    public func updated(with scanned: [ClaudeSession], now: Date) -> Self {
        let ordered = scanned.sorted { ($0.displayName, $0.id) < ($1.displayName, $1.id) }
        var seen: [String: Date] = [:]
        for session in ordered {
            if session.isWorking {
                seen[session.id] = now
            } else if session.isActive(now: now, grace: Self.lingerSeconds) {
                // It stopped between two scans, or just before the app looked: count from the real stop time.
                seen[session.id] = max(lastWorking[session.id] ?? .distantPast, session.statusUpdatedAt)
            } else if let previous = lastWorking[session.id] {
                seen[session.id] = previous
            }
        }
        return Self(sessions: ordered, lastWorking: seen)
    }

    public func visible(pinned: [String], now: Date) -> [Row] {
        sessions.compactMap { session in
            let isPinned = pinned.contains(session.id)
            let isShown = session.isWorking || isPinned || isLingering(session, now: now)
            return isShown ? Row(session: session, isPinned: isPinned) : nil
        }
    }

    private func isLingering(_ session: ClaudeSession, now: Date) -> Bool {
        guard let last = lastWorking[session.id] else { return false }
        return now.timeIntervalSince(last) < Self.lingerSeconds
    }
}

