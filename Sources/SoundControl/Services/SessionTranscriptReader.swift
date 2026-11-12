import Foundation
import SoundControlCore

/// Reads what each session is up to from the end of its transcript in `~/.claude/projects`:
/// the topic the terminal tab shows, and the latest messages and tool calls for the terminal-style feed.
/// Only the last few hundred KB are read, and only after the transcript changed, so large files stay cheap.
@MainActor
final class SessionTranscriptReader {
    private static let tailBytes = 512 * 1024
    private static let activeRefresh: TimeInterval = 1
    /// Just after a session stops its reply lands in the transcript, so it keeps the fast refresh for a while.
    private static let activeGrace: TimeInterval = 30
    private static let restingRefresh: TimeInterval = 15
    private static let retryInterval: TimeInterval = 30

    private struct Entry {
        var file: URL?
        var modified: Date?
        var checkedAt: Date
        var digest: TranscriptDigest
    }

    struct Reading {
        let sessions: [ClaudeSession]
        let activity: [String: [TranscriptLine]]
    }

    private let root = ClaudePaths.projects
    private var entries: [String: Entry] = [:]

    /// The sessions with their topics filled in, and each session's latest activity. Closed sessions are forgotten.
    /// While nothing shows the feed (`isWatched` false) every session uses the slow refresh, since only titles are needed.
    func read(_ sessions: [ClaudeSession], now: Date, isWatched: Bool) -> Reading {
        let open = Set(sessions.map(\.id))
        entries = entries.filter { open.contains($0.key) }
        var activity: [String: [TranscriptLine]] = [:]
        let titled = sessions.map { session -> ClaudeSession in
            let digest = refresh(session, now: now, isWatched: isWatched)
            activity[session.id] = digest.activity
            return session.withTitle(digest.title)
        }
        return Reading(sessions: titled, activity: activity)
    }

    private func refresh(_ session: ClaudeSession, now: Date, isWatched: Bool) -> TranscriptDigest {
        var entry = entries[session.id] ?? Entry(file: nil, modified: nil, checkedAt: .distantPast, digest: .empty)
        defer { entries[session.id] = entry }
        if entry.file == nil {
            guard now.timeIntervalSince(entry.checkedAt) >= Self.retryInterval else { return entry.digest }
            entry.checkedAt = now
            entry.file = findTranscript(session.id)
        }
        guard let file = entry.file else { return entry.digest }
        let isActive = isWatched && session.isActive(now: now, grace: Self.activeGrace)
        let interval = isActive ? Self.activeRefresh : Self.restingRefresh
        let isFirstRead = entry.digest == .empty
        guard isFirstRead || now.timeIntervalSince(entry.checkedAt) >= interval else { return entry.digest }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard isFirstRead || modified != entry.modified else { return entry.digest }
        entry.checkedAt = now
        entry.modified = modified
        // Parsed objects are autoreleased; draining here keeps each read's garbage from piling up.
        if let digest = autoreleasepool(invoking: { readTail(file).map { ClaudeTranscript.digest(inTail: $0) } }) {
            entry.digest = digest
        }
        return entry.digest
    }

    /// Transcripts live in one folder per project, so the session id is searched across them.
    private func findTranscript(_ id: String) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent("\(id).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func readTail(_ file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        return try? handle.readToEnd()
    }
}
