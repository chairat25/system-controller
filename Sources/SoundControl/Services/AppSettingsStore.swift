import Foundation
import SoundControlCore

/// Reads and writes `app.json` in the app's Application Support folder.
enum AppSettingsStore {
    static let fileURL = ConfigStore.applicationSupport().appendingPathComponent("app.json")

    /// A missing or unreadable file means defaults.
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
