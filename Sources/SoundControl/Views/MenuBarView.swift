import AppKit
import SwiftUI

/// The popover under the menu-bar icon: one tab per module, each with its own controls.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var tab: ModuleTab = .soundControl

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Module", selection: $tab) {
                ForEach(ModuleTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .soundControl: SoundPanel()
            case .dev: DevPanel()
            }

            Divider()
            HStack {
                if tab == .soundControl {
                    Button("Open Sound Control…") {
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                    .keyboardShortcut(",")
                }
                Spacer()
                Button("Quit") {
                    model.flushSave()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
