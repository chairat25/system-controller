import Foundation
import SoundControlCore

/// Reads and writes `limit-guard.json` in the app's Application Support folder.
enum LimitGuardStore {
    static let fileURL = ConfigStore.applicationSupport().appendingPathComponent("limit-guard.json")

    /// A missing or unreadable file means defaults.
    static func load() -> LimitGuardSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(LimitGuardSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: LimitGuardSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
