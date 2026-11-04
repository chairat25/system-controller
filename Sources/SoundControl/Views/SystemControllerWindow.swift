import SwiftUI

/// Top-level tabs of System Controller. A new module adds a case here and a branch in `content(for:)`.
enum ModuleTab: String, CaseIterable, Identifiable {
    case soundControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soundControl: "Sound Control"
        }
    }

    var symbol: String {
        switch self {
        case .soundControl: "waveform.circle.fill"
        }
    }
}

/// The main window: one tab per module, Sound Control first.
struct SystemControllerWindow: View {
    @State private var tab: ModuleTab = .soundControl

    var body: some View {
        TabView(selection: $tab) {
            ForEach(ModuleTab.allCases) { module in
                content(for: module)
                    .tabItem { Label(module.title, systemImage: module.symbol) }
                    .tag(module)
            }
        }
    }

    @ViewBuilder
    private func content(for module: ModuleTab) -> some View {
        switch module {
        case .soundControl: MainWindow()
        }
    }
}
