import AppKit
import SwiftUI

/// The popover under the menu-bar icon: one tab per module, each with its own controls,
/// and a gear beside the tabs for the settings of the whole app.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    /// Height of the current page, measured so the popup is as tall as it needs and no taller than the screen.
    @State private var pageHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.control) {
            if model.isShowingAppSettings {
                SubpageHeader(title: "Settings") { model.isShowingAppSettings = false }
            } else {
                tabBar
            }
            ScrollView {
                page
                    // Lets every line wrap instead of being cut off with "…".
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(pageHeight, Self.maxPageHeight))

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
        .frame(width: Self.width)
    }

    @ViewBuilder
    private var page: some View {
        if model.isShowingAppSettings {
            AppSettingsPage()
        } else {
            switch model.menuTab {
            case .control: SoundPanel()
            case .screenSaver: ScreenSaverPanel()
            case .dev: DevPanel()
            }
        }
    }

    /// The tallest the page may get on this screen; the tab bar, the footer and the popup's own margins
    /// take the rest. Anything longer scrolls.
    private static var maxPageHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? Layout.fallbackScreenHeight
        return max(screen - Layout.chromeHeight, Layout.minimumPageHeight)
    }

    private static let width: CGFloat = 340

    private enum Layout {
        static let chromeHeight: CGFloat = 150
        static let minimumPageHeight: CGFloat = 240
        static let fallbackScreenHeight: CGFloat = 800
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

/// Settings for the whole app, not one module: general, behavior, permissions and about.
private struct AppSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PopoverSection("General") {
                SettingToggle(title: "Launch at login", systemImage: "power", isOn: model.isLaunchAtLoginEnabled,
                              onChange: { model.setLaunchAtLogin($0) })
                SettingRow("Open this popup", systemImage: "command") {
                    ShortcutRecorder(shortcut: model.appSettings.popupShortcut,
                                     onChange: { value in model.updateAppSettings { $0.withPopupShortcut(value) } },
                                     onRecordingChange: { model.setShortcutRecording($0) })
                }
                if let problem = model.popupShortcutProblem {
                    Footnote(problem, tone: Theme.warning)
                }
                Footnote("Works from any app. It opens on the Sound tab; press it again to close.")
            }
            PopoverSection("Behavior") {
                SettingToggle(title: "Instant sounds", detail: "Keeps audio ready while you use the Mac",
                              systemImage: "bolt", isOn: model.config.keepAudioReady,
                              onChange: { value in model.update { $0.withKeepAudioReady(value) } })
                SettingToggle(title: "One sound per moment", detail: "Plays only the first of events that happen together",
                              systemImage: "1.circle", isOn: model.config.avoidOverlap,
                              onChange: { value in model.update { $0.withAvoidOverlap(value) } })
            }
            PopoverSection("Permissions") {
                SettingRow("Input Monitoring", detail: "Keyboard and mouse triggers", systemImage: "keyboard") {
                    permissionStatus(model.hasInputPermission) { PrivacySettings.openInputMonitoring() }
                }
                SettingRow("Accessibility", detail: "Keyboard lock and screen saver", systemImage: "accessibility") {
                    permissionStatus(KeyboardBlocker.hasPermission) { PrivacySettings.openAccessibility() }
                }
            }
            PopoverSection("About") {
                SettingRow("Version", systemImage: "info.circle") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                SettingToggle(title: "Auto-update",
                              detail: "Installs new releases automatically when unlocked",
                              systemImage: "arrow.triangle.2.circlepath",
                              isOn: model.appSettings.autoUpdateEnabled,
                              onChange: { model.setAutoUpdate($0) })
                SettingRow("Updates", detail: model.updater.statusText, systemImage: "arrow.down.circle") {
                    Button("Check Now") { model.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(model.updater.isBusyUpdating)
                }
                SettingRow("Triggers, packs, quiet hours and more", systemImage: "macwindow") {
                    OpenWindowLink(title: "Open")
                }
            }
        }
    }

    /// Allowed, or a way to fix it. The state is read from macOS, never assumed.
    @ViewBuilder
    private func permissionStatus(_ isGranted: Bool, open: @escaping () -> Void) -> some View {
        if isGranted {
            StatusIndicator(text: "Allowed", level: .good)
        } else {
            Button("Allow…", action: open).controlSize(.small)
        }
    }
}
