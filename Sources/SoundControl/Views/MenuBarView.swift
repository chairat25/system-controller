import AppKit
import SwiftUI

/// The popover under the menu-bar icon: one tab per module, each with its own controls.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var tab: ModuleTab = .control

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Module", selection: $tab) {
                ForEach(ModuleTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .control: SoundPanel()
            case .screenSaver: ScreenSaverPanel()
            case .dev: DevPanel()
            }

            Divider()
            Toggle("Launch at login", isOn: Binding(get: { model.isLaunchAtLoginEnabled },
                                                    set: { model.setLaunchAtLogin($0) }))
                .font(.callout)
            HStack {
                if tab == .control {
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
