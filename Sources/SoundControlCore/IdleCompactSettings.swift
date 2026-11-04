import Foundation

/// Auto `/compact` after Claude goes idle. Stored as JSON in `~/.claude/idle-compact.json`,
/// which the Stop hook reads on every turn, so changes apply from the next turn.
public struct IdleCompactSettings: Codable, Sendable, Equatable {
    public static let defaultMinutes = 15
    public static let minimumMinutes = 1
    public static let maximumMinutes = 120
    public static let `default` = IdleCompactSettings(isEnabled: true, idleMinutes: defaultMinutes)

    public var isEnabled: Bool
    public private(set) var idleMinutes: Int

    public var idleSeconds: Int { idleMinutes * 60 }

    public init(isEnabled: Bool, idleMinutes: Int) {
        self.isEnabled = isEnabled
        self.idleMinutes = Self.clamp(idleMinutes)
    }

    /// Missing or out-of-range fields fall back to defaults instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        let minutes = try container.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? Self.defaultMinutes
        self.init(isEnabled: isEnabled, idleMinutes: minutes)
    }

    public func withEnabled(_ isEnabled: Bool) -> Self {
        Self(isEnabled: isEnabled, idleMinutes: idleMinutes)
    }

    public func withIdleMinutes(_ minutes: Int) -> Self {
        Self(isEnabled: isEnabled, idleMinutes: minutes)
    }

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minimumMinutes), maximumMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "enabled"
        case idleMinutes
    }
}
