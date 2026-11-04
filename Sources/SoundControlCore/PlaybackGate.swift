import Foundation

/// Why a trigger did or did not make a sound. Shown in the activity log.
public enum GateDecision: Equatable, Sendable {
    case play
    case skipped(SkipReason)
}

public enum SkipReason: String, Sendable {
    case notListening = "Listening is off"
    case triggerOff = "Trigger is off"
    case quietHours = "Quiet hours"
    case cooldown = "Too soon after last play"
    case overlap = "Another sound was already playing"
    case noSound = "No sound available"
    case asleep = "Mac is asleep"

    public var isWorthLogging: Bool {
        // Triggers the user switched off would flood the log (e.g. every key press).
        self != .triggerOff && self != .cooldown
    }
}

public enum PlaybackGate {
    /// Events closer together than this count as one burst when `avoidOverlap` is on.
    public static let burstWindow: TimeInterval = 0.35
    /// Sounds may still start this long after the Mac begins to sleep, so "Mac sleeps" is heard.
    public static let sleepGrace: TimeInterval = 5

    /// - Parameter lastEventSound: when the last non-chatty sound started, for burst suppression.
    /// - Parameter asleepSince: when the Mac began to sleep, or nil while it is awake. Events arriving
    ///   during a dark wake (lid closed, Wi-Fi reconnecting) find no usable audio output.
    public static func decide(
        _ trigger: TriggerID, config: AppConfig, now: Date, lastPlayed: Date?,
        lastEventSound: Date? = nil, asleepSince: Date? = nil, calendar: Calendar = .current
    ) -> GateDecision {
        guard config.isListening else { return .skipped(.notListening) }
        guard config.isEnabled(trigger) else { return .skipped(.triggerOff) }
        if let asleepSince, now.timeIntervalSince(asleepSince) >= sleepGrace {
            return .skipped(.asleep)
        }
        if config.quietHours.contains(minuteOfDay: minuteOfDay(now, calendar: calendar)) {
            return .skipped(.quietHours)
        }
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < TriggerCatalog.info(for: trigger).cooldown {
            return .skipped(.cooldown)
        }
        guard !SoundResolver.candidates(for: trigger, in: config).isEmpty else { return .skipped(.noSound) }
        if config.avoidOverlap, !TriggerCatalog.info(for: trigger).isChatty,
           let lastEventSound, now.timeIntervalSince(lastEventSound) < burstWindow {
            return .skipped(.overlap)
        }
        return .play
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Effective 0...1 gain for a trigger.
    public static func gain(for trigger: TriggerID, config: AppConfig) -> Float {
        Float(config.masterVolume * config.setting(for: trigger).volume)
    }
}
