import Foundation

/// Decides which sessions get `/compact` after sitting idle. Pure: the caller feeds every scan and types the
/// command into the returned sessions' terminals.
///
/// A session is only compacted after activity the app saw itself, so sessions that were already idle when the
/// app started are left alone, and the status changes caused by `/compact` itself never trigger another one.
public struct IdleCompactor: Sendable, Equatable {
    public static let initial = IdleCompactor(tracks: [:])
    /// Status changes this soon after sending `/compact` come from the compaction, not from the owner.
    public static let settleSeconds: TimeInterval = 300

    private struct Track: Sendable, Equatable {
        var lastStatusChange: Date
        var isArmed: Bool
        var compactedAt: Date?
    }

    private let tracks: [String: Track]

    private init(tracks: [String: Track]) {
        self.tracks = tracks
    }

    public func advancing(sessions: [ClaudeSession], settings: IdleCompactSettings,
                          now: Date) -> (IdleCompactor, [ClaudeSession]) {
        var next: [String: Track] = [:]
        var due: [ClaudeSession] = []
        for session in sessions {
            guard var track = tracks[session.id] else {
                next[session.id] = Track(lastStatusChange: session.statusUpdatedAt, isArmed: false, compactedAt: nil)
                continue
            }
            if session.statusUpdatedAt != track.lastStatusChange {
                track.lastStatusChange = session.statusUpdatedAt
                let isFromCompaction = track.compactedAt.map {
                    session.statusUpdatedAt.timeIntervalSince($0) < Self.settleSeconds
                } ?? false
                if !isFromCompaction { track.isArmed = true }
            }
            let idle = now.timeIntervalSince(session.statusUpdatedAt)
            if settings.isEnabled, track.isArmed, !session.isWorking, idle >= TimeInterval(settings.idleSeconds) {
                track.isArmed = false
                track.compactedAt = now
                due.append(session)
            }
            next[session.id] = track
        }
        return (Self(tracks: next), due)
    }
}
