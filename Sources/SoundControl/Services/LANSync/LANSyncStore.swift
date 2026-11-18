import Foundation
import SoundControlCore

/// Reads and writes `lansync.json` in the app's Application Support folder.
enum LANSyncStore {
    static let fileURL = ConfigStore.applicationSupport().appendingPathComponent("lansync.json")

    /// A missing or unreadable file means defaults.
    static func load() -> LANSyncSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(LANSyncSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: LANSyncSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
