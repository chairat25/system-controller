import Foundation

/// How a keyboard lock opens again.
public enum UnlockMethod: Sendable, Equatable {
    /// Hold the on-screen button with the mouse. Anyone can do it, so the lock times out.
    case holdButton
    /// Touch ID or the login password. Only the owner can do it, so the lock never times out.
    case ownerAuthentication
}

/// A keyboard lock: keys are ignored until the user unlocks.
/// A `holdButton` lock also ends after `maxDuration`, so a broken mouse can never leave the keyboard dead.
public struct KeyboardLock: Sendable, Equatable {
    public static let maxDuration: TimeInterval = 10 * 60
    /// How long the Unlock button must be held, so a stray trackpad tap does not unlock.
    public static let holdToUnlock: TimeInterval = 1

    private static let keyboardTriggers: Set<TriggerID> = [
        .keyTyped, .returnKey, .deleteKey, .spaceKey, .capsLockOn, .capsLockOff
    ]

    public let lockedAt: Date
    public let unlock: UnlockMethod

    public init(lockedAt: Date, unlock: UnlockMethod = .holdButton) {
        self.lockedAt = lockedAt
        self.unlock = unlock
    }

    /// Only a `holdButton` lock counts down and times out.
    public var expires: Bool {
        unlock == .holdButton
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, Self.maxDuration - now.timeIntervalSince(lockedAt))
    }

    public func hasExpired(at now: Date) -> Bool {
        expires && remaining(at: now) == 0
    }

    /// Wiping the keys should not set off key sounds.
    public static func silences(_ trigger: TriggerID) -> Bool {
        keyboardTriggers.contains(trigger)
    }
}
