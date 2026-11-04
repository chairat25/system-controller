import SwiftUI

/// Top-level tabs of the System Controller window. Each module owns its own page and controls.
/// A new module adds a case here and a branch in `SystemControllerWindow.content(for:)`.
enum ModuleTab: String, CaseIterable, Identifiable {
    case soundControl
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soundControl: "Sound Control"
        case .dev: "Dev"
        }
    }

    var symbol: String {
        switch self {
        case .soundControl: "waveform.circle.fill"
        case .dev: "hammer.fill"
        }
    }
}
