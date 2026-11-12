import AppKit
import SwiftUI

/// The popover under the menu-bar icon: one tab per module, each with its own controls,
/// and a gear beside the tabs for the settings of the whole app.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isShowingAppSettings {
                SubpageHeader(title: "Settings") { model.isShowingAppSettings = false }
                AppSettingsPage()
            } else {
                tabBar
                switch model.menuTab {
                case .control: SoundPanel()
                case .screenSaver: ScreenSaverPanel()
                case .dev: DevPanel()
                }
            }

            Divider()
            HStack {
                if model.menuTab == .control, !model.isShowingAppSettings {
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

    private var tabBar: some View {
        HStack(spacing: 8) {
            Picker("Module", selection: Binding(get: { model.menuTab }, set: { model.menuTab = $0 })) {
                ForEach(ModuleTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button {
                model.isShowingAppSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }
}

/// Title row of a page inside the popup, with a way back.
struct SubpageHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Back")
            Text(title).font(.headline)
        }
    }
}

/// Settings for the whole app, not one module.
private struct AppSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHORTCUT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            LabeledContent("Open this popup") {
                ShortcutRecorder(shortcut: model.appSettings.popupShortcut,
                                 onChange: { value in model.updateAppSettings { $0.withPopupShortcut(value) } },
                                 onRecordingChange: { model.setShortcutRecording($0) })
            }
            if let problem = model.popupShortcutProblem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
            }
            Text("Works from any app. It opens on the Control tab; press it again to close.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("GENERAL").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: Binding(get: { model.isLaunchAtLoginEnabled },
                                                    set: { model.setLaunchAtLogin($0) }))
        }
    }
}
