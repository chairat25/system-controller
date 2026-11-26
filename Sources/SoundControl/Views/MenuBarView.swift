import AppKit
import OSLog
import SwiftUI

/// The popover under the menu-bar icon: one tab per module, each with its own controls,
/// and a gear beside the tabs for the settings of the whole app.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    /// Height of the current page, measured so the popup is as tall as it needs and no taller than the screen.
    @State private var pageHeight: CGFloat = 0
    /// False while the popup has been closed for a while: its views are dropped and a blank of the same size
    /// stands in, so a closed popup holds no view tree, layers or images (about 14 MB).
    @State private var isContentLoaded = true
    @State private var contentSize = CGSize.zero
    @State private var unloadTask: Task<Void, Never>?
    @State private var shownAt: ContinuousClock.Instant?

    /// Reopening within this long finds everything still built, so quick toggles never rebuild.
    private static let unloadDelay: Duration = .seconds(10)
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "Popup")

    var body: some View {
        Group {
            if isContentLoaded {
                popup
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
                    .onAppear(perform: logRebuild)
            } else {
                Color.clear.frame(width: contentSize.width, height: contentSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WindowVisibilityReader(onChange: visibilityChanged))
    }

    private func visibilityChanged(_ isVisible: Bool) {
        unloadTask?.cancel()
        unloadTask = nil
        guard !isVisible else {
            if !isContentLoaded {
                shownAt = .now
                isContentLoaded = true
            }
            return
        }
        unloadTask = Task { @MainActor in
            try? await Task.sleep(for: Self.unloadDelay)
            guard !Task.isCancelled, isContentLoaded else { return }
            isContentLoaded = false
            // The dropped views free their memory on the next turn; then hand the pages back to the system.
            DispatchQueue.main.async { malloc_zone_pressure_relief(nil, 0) }
        }
    }

    private func logRebuild() {
        guard let shownAt else { return }
        let elapsed = (ContinuousClock.now - shownAt).components
        let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        Self.logger.notice("Popup rebuilt \(milliseconds) ms after showing")
        self.shownAt = nil
    }

    private var popup: some View {
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
            .clipped()

            Divider()
            HStack {
                if model.menuTab == .control, !model.isShowingAppSettings {
                    Button(L("Open Sound Control…")) { model.showMainWindow() }
                    .keyboardShortcut(",")
                }
                Spacer()
                Button(L("Quit")) {
                    model.flushSave()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        // The popup is always exactly this wide and as tall as its page. Anything inside that asks for more width
        // grows to the right only, so it can never push the page against the left or top edge.
        .frame(width: Self.width - 2 * Self.margin, alignment: .topLeading)
        .padding(Self.margin)
        .fixedSize()
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

    private static let width: CGFloat = 380
    private static let margin: CGFloat = 16

    private enum Layout {
        static let chromeHeight: CGFloat = 150
        static let minimumPageHeight: CGFloat = 240
        static let fallbackScreenHeight: CGFloat = 800
    }

    private var tabBar: some View {
        HStack(spacing: Spacing.related) {
            ModuleTabBar(selection: model.menuTab) { model.menuTab = $0 }
            Button {
                model.isShowingAppSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L("Settings"))
        }
    }
}

/// The module tabs as one segmented strip that always fits the width it is given: the segments share it equally
/// and a long label shrinks a little instead of widening the popup. (A segmented `Picker` keeps its own minimum
/// width, which with the gear beside it was wider than the popup and shoved the whole page to the left edge.)
struct ModuleTabBar: View {
    let selection: ModuleTab
    let onSelect: (ModuleTab) -> Void

    private static let inset: CGFloat = 2
    private static let radius: CGFloat = 8

    var body: some View {
        HStack(spacing: Self.inset) {
            ForEach(ModuleTab.allCases) { tab in
                segment(tab)
            }
        }
        .padding(Self.inset)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Module"))
    }

    private func segment(_ tab: ModuleTab) -> some View {
        let isSelected = tab == selection
        return Button { onSelect(tab) } label: {
            Text(L(tab.title))
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Self.radius - Self.inset, style: .continuous)
                            .fill(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .help(L("Back"))
            Text(L(title)).font(.headline)
        }
    }
}

/// Settings for the whole app, not one module: general, behavior, permissions and about.
private struct AppSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PopoverSection(L("General")) {
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
            PopoverSection(L("Behavior")) {
                SettingToggle(title: "Instant sounds", detail: "Keeps audio ready while you use the Mac",
                              systemImage: "bolt", isOn: model.config.keepAudioReady,
                              onChange: { value in model.update { $0.withKeepAudioReady(value) } })
                SettingToggle(title: "One sound per moment", detail: "Plays only the first of events that happen together",
                              systemImage: "1.circle", isOn: model.config.avoidOverlap,
                              onChange: { value in model.update { $0.withAvoidOverlap(value) } })
            }
            PopoverSection(L("Sync")) {
                SettingToggle(title: "Sync wallpaper", detail: "Same wallpaper on every paired Mac",
                              systemImage: "photo.on.rectangle", isOn: model.lanSync.settings.isWallpaperSyncOn,
                              onChange: { value in model.lanSync.update { $0.withWallpaperSync(value) } })
                SettingToggle(title: "Mascot roams between Macs", detail: "Walks across to a paired Mac",
                              systemImage: "figure.walk", isOn: model.lanSync.settings.isMascotRoamingOn,
                              onChange: { value in model.lanSync.update { $0.withMascotRoaming(value) } })
                if model.lanSync.settings.isMascotRoamingOn {
                    // Each Mac picks its own animal; a visitor keeps the look of the Mac it came from.
                    MascotGrid(selection: model.screenSaver.activeMascot) { mascot in
                        model.updateScreenSaver { $0.withMascot(mascot) }
                    }
                    Footnote("This Mac's animal. Each Mac picks its own; the same one walks on the screen saver.")
                }
                ForEach(model.lanSync.settings.pairedPeers) { peer in
                    PairedMacRow(peer: peer, isConnected: model.lanSync.connectedPeerIDs.contains(peer.id),
                                 version: model.lanSync.peerVersions[peer.id],
                                 setSide: { side in model.lanSync.update { $0.withSide(side, for: peer.id) } },
                                 unpair: { model.lanSync.unpair(peer.id) })
                }
                PairingControls(pairing: model.lanSync.pairing)
                if let problem = model.lanSync.problem {
                    Footnote(problem, tone: Theme.warning)
                }
            }
            PerformanceSection()
            PopoverSection(L("Permissions")) {
                SettingRow("Input Monitoring", detail: "Keyboard and mouse triggers", systemImage: "keyboard") {
                    permissionStatus(model.hasInputPermission) { PrivacySettings.openInputMonitoring() }
                }
                SettingRow("Accessibility", detail: "Keyboard lock and screen saver", systemImage: "accessibility") {
                    permissionStatus(KeyboardBlocker.hasPermission) { PrivacySettings.openAccessibility() }
                }
            }
            PopoverSection(L("About")) {
                SettingRow("Language", systemImage: "globe") {
                    LanguagePicker(selection: model.appSettings.language, onSelect: model.setLanguage)
                }
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
                    Button(L("Check Now")) { model.checkForUpdates() }
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
            Button(L("Allow…"), action: open).controlSize(.small)
        }
    }
}
