import CoreGraphics
import Foundation
import Observation
import OSLog
import SoundControlCore

/// Watches the Claude Code sessions running on this Mac and acts on them.
///
/// Every second it reads Claude Code's `sessions` folder (who is working); every minute it asks Anthropic how much
/// of the five-hour window is used. When little quota is left, each working session is asked for a handoff note
/// and then `/compact`. Sessions left idle long enough get `/compact` too, unless an older Stop hook already does that.
@MainActor
@Observable
final class ClaudeSessionMonitor {
    private static let pollInterval: TimeInterval = 1
    /// Reading a terminal costs a fraction of a second, so at most a few expanded sessions are mirrored.
    private static let mirroredSessions = 3
    private static let mirroredLines = 12
    private static let quotaInterval: TimeInterval = 60
    private static let quotaBackoff: TimeInterval = 300

    private(set) var board = ClaudeSessionBoard.empty
    /// Latest messages and tool calls per session id, for the terminal-style feed.
    private(set) var activity: [String: [TranscriptLine]] = [:]
    /// The terminal's own text per session id, newest lines last. Only filled for expanded sessions while the screen saver is up.
    private(set) var screens: [String: [String]] = [:]
    /// Sessions opened on the screen saver to watch live. Shared by every display; cleared when the screen saver closes.
    private(set) var expanded: Set<String> = []
    private(set) var quota: ClaudeQuota?
    /// Why the quota is unknown, shown in the Dev tab.
    private(set) var quotaProblem: String?
    /// True when this Mac still has the older Stop hook that sends /compact on idle, so the app leaves that to it.
    private(set) var hasIdleCompactHook = false
    /// The last automatic /compact on idle, shown in the Dev tab.
    private(set) var idleNote: String?
    /// The last thing the guard did, shown in the Dev tab.
    private(set) var guardNote: String?

    @ObservationIgnored private let transcripts = SessionTranscriptReader()
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var limitGuard = LimitGuard.idle
    @ObservationIgnored private var idleCompactor = IdleCompactor.initial
    @ObservationIgnored private var settings: () -> LimitGuardSettings = { .default }
    @ObservationIgnored private var idleSettings: () -> IdleCompactSettings = { .default }
    @ObservationIgnored private var isLocked: () -> Bool = { false }
    @ObservationIgnored private var quotaFetchedAt: Date?
    @ObservationIgnored private var nextQuotaFetch = Date.distantPast
    @ObservationIgnored private var isFetchingQuota = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "ClaudeSessionMonitor")

    func start(settings: @escaping () -> LimitGuardSettings,
               idleSettings: @escaping () -> IdleCompactSettings,
               isLocked: @escaping () -> Bool = { false }) {
        guard timer == nil else { return }
        self.settings = settings
        self.idleSettings = idleSettings
        self.isLocked = isLocked
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    /// The screen saver asks for live terminal text while it is on screen, and lets go when it closes.
    func beginWatching() {
        watchers += 1
        captureScreens()
    }

    func endWatching() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0 else { return }
        if !screens.isEmpty { screens = [:] }
        if !expanded.isEmpty { expanded = [] }
    }

    /// Opens a session's live view on the screen saver, or folds it back to its name chip.
    func toggleExpanded(_ id: String) {
        expanded = expanded.contains(id) ? expanded.subtracting([id]) : expanded.union([id])
        captureScreens()
    }

    /// Feeds are read every second only while someone is looking at one.
    private var isFeedVisible: Bool { watchers > 0 && !expanded.isEmpty }

    private func captureScreens() {
        guard watchers > 0, !isCapturing else { return }
        let targets = board.sessions.filter {
            expanded.contains($0.id) && $0.isActive(now: Date(), grace: ClaudeSessionBoard.lingerSeconds)
        }
        .prefix(Self.mirroredSessions)
        guard !targets.isEmpty else {
            if !screens.isEmpty { screens = [:] }
            return
        }
        isCapturing = true
        let idsByPid = Dictionary(targets.map { ($0.pid, $0.id) }, uniquingKeysWith: { first, _ in first })
        Task { [weak self] in
            let captured = await TerminalScreenReader.capture(processes: Array(idsByPid.keys))
            guard let self else { return }
            isCapturing = false
            guard watchers > 0 else { return }
            let next = Dictionary(captured.compactMap { pid, text in
                idsByPid[pid].map { ($0, TerminalScreen.conversationTail(text, limit: Self.mirroredLines)) }
            }, uniquingKeysWith: { first, _ in first })
            if next != screens { screens = next }
        }
    }

    private func scan() {
        let now = Date()
        let reading = transcripts.read(ClaudeSession.collapsed(Self.readSessions()), now: now, isWatched: isFeedVisible)
        let sessions = reading.sessions
        // Observation redraws every reader on any assignment, so unchanged values are not written back each second.
        if reading.activity != activity { activity = reading.activity }
        captureScreens()
        let nextBoard = board.updated(with: sessions, now: now)
        if nextBoard != board { board = nextBoard }
        refreshQuota(now: now)
        let screenLocked = isLocked()
        let (next, actions) = limitGuard.advancing(
            quota: quota, sessions: sessions, settings: settings(),
            handoffWritten: { id, since in Self.isHandoffWritten(id, since: since) }, now: now)
        limitGuard = next
        if !screenLocked {
            actions.forEach(run)
            compactIdle(sessions, now: now)
        }
    }

    // MARK: - Quota

    private func refreshQuota(now: Date) {
        // A reading older than the cache limit, or from a window that already reset, is no longer trusted.
        if let quota, quota.resetsAt <= now || now.timeIntervalSince(quotaFetchedAt ?? .distantPast) > ClaudeQuota.maxAge {
            self.quota = nil
        }
        guard !isFetchingQuota, now >= nextQuotaFetch else { return }
        isFetchingQuota = true
        hasIdleCompactHook = Self.detectIdleCompactHook()
        Task { [weak self] in
            let result = await ClaudeQuotaClient.fetch()
            guard let self else { return }
            isFetchingQuota = false
            let fetchedAt = Date()
            switch result {
            case .success(let quota):
                self.quota = quota
                quotaFetchedAt = fetchedAt
                quotaProblem = nil
                nextQuotaFetch = fetchedAt.addingTimeInterval(Self.quotaInterval)
            case .failure(let failure):
                quotaProblem = failure.message
                let wait = failure == .rejected(429) ? Self.quotaBackoff : Self.quotaInterval
                nextQuotaFetch = fetchedAt.addingTimeInterval(wait)
            }
        }
    }

    // MARK: - Idle /compact

    private func compactIdle(_ sessions: [ClaudeSession], now: Date) {
        var settings = idleSettings()
        // The owner may be typing a prompt that is not sent yet; /compact would land in the middle of it.
        // Holding off keeps the session armed, so it fires once the keyboard and mouse sit still.
        if hasIdleCompactHook || Self.secondsSinceInput() < Self.inputQuietSeconds {
            settings = settings.withEnabled(false)
        }
        let (next, due) = idleCompactor.advancing(sessions: sessions, settings: settings, now: now)
        idleCompactor = next
        for session in due {
            Task { [weak self] in
                let isSent = await TerminalDelivery.send("/compact", toProcess: session.pid)
                self?.idleNote = isSent ? "Sent /compact to \(session.displayName) after it sat idle"
                    : "Could not reach the terminal of \(session.displayName)"
            }
        }
    }

    private static let inputQuietSeconds: TimeInterval = 120

    /// Seconds since the last key press, click or mouse move anywhere on this Mac.
    private static func secondsSinceInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// An older setup does idle /compact from a Stop hook in Claude Code's settings. Doing it twice would waste quota.
    private static func detectIdleCompactHook() -> Bool {
        guard let data = try? Data(contentsOf: ClaudePaths.settings) else { return false }
        return String(decoding: data, as: UTF8.self).contains("idle-compact-start")
    }

    // MARK: - Guard actions

    private func run(_ action: LimitGuardAction) {
        switch action {
        case .handoff(let session):
            let path = Self.handoffURL(session.id).path
            try? FileManager.default.createDirectory(at: ClaudePaths.handoffs, withIntermediateDirectories: true)
            deliver(LimitGuard.handoffPrompt(path: path), to: session, done: "Asked \(session.displayName) for a handoff note")
        case .compact(let session):
            let command = LimitGuard.compactCommand(handoffPath: Self.handoffURL(session.id).path)
            deliver(command, to: session, done: "Sent /compact to \(session.displayName)")
        }
    }

    private func deliver(_ text: String, to session: ClaudeSession, done: String) {
        Task { [weak self] in
            let isSent = await TerminalDelivery.send(text, toProcess: session.pid)
            guard let self else { return }
            if isSent {
                guardNote = done
            } else {
                // No terminal tab this app can reach owns this process, so do not retry it every scan.
                limitGuard = limitGuard.skipping(session.id)
                guardNote = "Could not reach the terminal of \(session.displayName)"
                logger.error("No terminal found for pid \(session.pid, privacy: .public)")
            }
        }
    }

    // MARK: - Reading

    /// Session files whose process is gone are left behind by Claude, so each pid is checked.
    private static func readSessions() -> [ClaudeSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: ClaudePaths.sessions, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), let session = ClaudeSession.parse(data),
                  isAlive(session.pid) else { return nil }
            return session
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func handoffURL(_ sessionID: String) -> URL {
        ClaudePaths.handoffs.appendingPathComponent("\(sessionID).md")
    }

    private static func isHandoffWritten(_ sessionID: String, since: Date) -> Bool {
        let modified = try? handoffURL(sessionID).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return (modified ?? nil).map { $0 >= since } ?? false
    }
}
