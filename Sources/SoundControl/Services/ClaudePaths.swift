import Foundation

/// Where Claude Code keeps its files on this Mac: `$CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`.
enum ClaudePaths {
    static let configDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }()

    static var sessions: URL { configDirectory.appendingPathComponent("sessions", isDirectory: true) }
    static var projects: URL { configDirectory.appendingPathComponent("projects", isDirectory: true) }
    static var handoffs: URL { configDirectory.appendingPathComponent("handoffs", isDirectory: true) }
    static var settings: URL { configDirectory.appendingPathComponent("settings.json") }
    static var credentials: URL { configDirectory.appendingPathComponent(".credentials.json") }
}
