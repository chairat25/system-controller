import Foundation
import SoundControlCore

/// Reads and writes `screensaver.json` in the app's Application Support folder.
enum ScreenSaverStore {
    static let fileURL = ConfigStore.applicationSupport().appendingPathComponent("screensaver.json")

    /// A missing or unreadable file means defaults.
    static func load() -> ScreenSaverSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(ScreenSaverSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: ScreenSaverSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
    }
}
