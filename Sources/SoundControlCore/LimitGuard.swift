import Foundation

/// How much of Claude's five-hour usage window is spent, as Anthropic's usage endpoint reports it.
public struct ClaudeQuota: Sendable, Equatable {
    /// A reading older than this may describe a window that has moved on, so it is not trusted.
    public static let maxAge: TimeInterval = 300

    public let usedPercent: Double
    public let resetsAt: Date

    public var remainingPercent: Double { min(max(100 - usedPercent, 0), 100) }

    public init(usedPercent: Double, resetsAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// Nil when the data is missing, too old, or describes a window that already reset.
    public static func parse(_ data: Data, fileAge: TimeInterval, now: Date) -> ClaudeQuota? {
        guard fileAge <= maxAge,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let window = object["five_hour"] as? [String: Any],
              let used = (window["utilization"] as? NSNumber)?.doubleValue, used.isFinite,
              let stamp = window["resets_at"] as? String,
              let resetsAt = ClaudeUsage.parse(stamp), resetsAt > now
        else { return nil }
        return ClaudeQuota(usedPercent: used, resetsAt: resetsAt)
    }
}

/// When the five-hour quota runs low, working sessions write a handoff note and then `/compact`.
/// Stored as JSON next to `screensaver.json`.
public struct LimitGuardSettings: Codable, Sendable, Equatable {
    public static let minimumPercent = 1
    public static let maximumPercent = 50
    public static let `default` = LimitGuardSettings(isEnabled: true, thresholdPercent: 5)

    public let isEnabled: Bool
    /// Acts when this much of the window or less is left.
    public let thresholdPercent: Int

    public init(isEnabled: Bool, thresholdPercent: Int) {
        self.isEnabled = isEnabled
        self.thresholdPercent = min(max(thresholdPercent, Self.minimumPercent), Self.maximumPercent)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled,
                  thresholdPercent: try container.decodeIfPresent(Int.self, forKey: .thresholdPercent)
                      ?? Self.default.thresholdPercent)
    }

    public func withEnabled(_ value: Bool) -> Self {
        Self(isEnabled: value, thresholdPercent: thresholdPercent)
    }

    public func withThreshold(percent: Int) -> Self {
        Self(isEnabled: isEnabled, thresholdPercent: percent)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, thresholdPercent
    }
}

/// What the app should type into a session's terminal.
public enum LimitGuardAction: Sendable, Equatable {
    case handoff(ClaudeSession)
    case compact(ClaudeSession)
}

/// Decides, scan by scan, which sessions get a handoff request and which get `/compact`. Pure: the caller
/// reads the quota and sessions, runs the returned actions, and feeds the new state into the next scan.
public struct LimitGuard: Sendable, Equatable {
    public static let idle = LimitGuard(window: nil, stages: [:])
    /// How long to wait for the handoff note before compacting anyway.
    public static let handoffTimeout: TimeInterval = 600

    private enum Stage: Sendable, Equatable {
        case handoffSent(Date)
        case done
    }

    private let window: Date?
    private let stages: [String: Stage]

    private init(window: Date?, stages: [String: Stage]) {
        self.window = window
        self.stages = stages
    }

    /// `handoffWritten(sessionID, since)` says whether that session's note was written after `since`.
    public func advancing(quota: ClaudeQuota?, sessions: [ClaudeSession], settings: LimitGuardSettings,
                          handoffWritten: (String, Date) -> Bool, now: Date) -> (LimitGuard, [LimitGuardAction]) {
        guard settings.isEnabled else { return (self, []) }
        var current = stages
        var currentWindow = window
        if let quota, quota.resetsAt != window {
            current = [:]
            currentWindow = quota.resetsAt
        }
        let open = Set(sessions.map(\.id))
        current = current.filter { open.contains($0.key) }

        let isLow = quota.map { $0.remainingPercent <= Double(settings.thresholdPercent) } ?? false
        var actions: [LimitGuardAction] = []
        for session in sessions {
            switch current[session.id] {
            case nil where isLow && session.isWorking:
                current[session.id] = .handoffSent(now)
                actions.append(.handoff(session))
            case .handoffSent(let sentAt)?:
                let isReady = handoffWritten(session.id, sentAt) || now.timeIntervalSince(sentAt) >= Self.handoffTimeout
                if !session.isWorking, isReady {
                    current[session.id] = .done
                    actions.append(.compact(session))
                }
            default:
                break
            }
        }
        return (Self(window: currentWindow, stages: current), actions)
    }

    /// Gives up on a session whose terminal could not be reached, so it is not retried every scan.
    public func skipping(_ sessionID: String) -> Self {
        Self(window: window, stages: stages.merging([sessionID: .done]) { _, new in new })
    }

    /// One line, so typing it submits it as a single message.
    public static func handoffPrompt(path: String) -> String {
        "Token budget is almost used up. Finish your current step, then write a handoff note to \(path): the goal, what is done, what is in progress, the next steps, and the key files, so a fresh session can continue. Then stop."
    }

    public static func compactCommand(handoffPath: String) -> String {
        "/compact Keep the goal, current state and next steps. Full handoff note: \(handoffPath)"
    }
}
