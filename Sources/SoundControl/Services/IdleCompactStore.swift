import Foundation
import SoundControlCore

/// Reads and writes `~/.claude/idle-compact.json`, the file the Stop hook reads on every turn.
enum IdleCompactStore {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/idle-compact.json")

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
