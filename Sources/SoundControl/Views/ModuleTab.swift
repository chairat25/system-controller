import SwiftUI

/// Top-level tabs of the System Controller popover. Each module owns its own page and controls.
/// A new module adds a case here and a branch in `MenuBarView`.
enum ModuleTab: String, CaseIterable, Identifiable {
    case control
    case screenSaver
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: "Sound"
        case .screenSaver: "Screen Saver"
        case .dev: "Developer"
        }
    }

    var symbol: String {
        switch self {
        case .control: "waveform.circle.fill"
        case .screenSaver: "heart.circle.fill"
        case .dev: "hammer.fill"
        }
    }
}
