import Foundation

/// How smoothly a held or thrown desktop mascot moves. Kept on this Mac only (in `app.json`), never synced.
public enum ThrowFrameRate: String, Codable, Sendable, CaseIterable, Identifiable {
    case display
    case fps120
    case fps60
    case fps30

    public static let `default` = ThrowFrameRate.display
    /// Used when the display does not report its refresh rate.
    public static let fallbackFramesPerSecond = 60

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .display: "Match display"
        case .fps120: "120 fps"
        case .fps60: "60 fps"
        case .fps30: "30 fps"
        }
    }

    /// Seconds per frame on a display that refreshes `displayFPS` times a second (0 when unknown).
    /// A fixed rate never runs faster than the display, which could not show the extra frames.
    public func interval(displayFPS: Int) -> TimeInterval {
        let display = displayFPS > 0 ? displayFPS : Self.fallbackFramesPerSecond
        let fps: Int = switch self {
        case .display: display
        case .fps120: min(120, display)
        case .fps60: min(60, display)
        case .fps30: min(30, display)
        }
        return 1.0 / Double(fps)
    }
}
