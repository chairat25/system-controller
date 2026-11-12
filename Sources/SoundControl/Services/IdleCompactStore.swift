import Foundation
import SoundControlCore

/// Reads and writes `idle-compact.json` in Claude Code's folder. The app reads it for its own idle /compact,
/// and an older Stop-hook setup reads the same file on every turn.
enum IdleCompactStore {
    static let fileURL = ClaudePaths.configDirectory.appendingPathComponent("idle-compact.json")

    /// A missing or unreadable file means defaults, the same as the hook.
    static func load() -> IdleCompactSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(IdleCompactSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: IdleCompactSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
