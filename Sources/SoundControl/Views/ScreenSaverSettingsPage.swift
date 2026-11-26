import SwiftUI
import SoundControlCore

/// The Screen Saver tab's settings page: background, mascot, widgets and their layout, the title, dimming,
/// what stays lit, the start shortcut and pinned sessions.
struct ScreenSaverSettingsPage: View {
    @Environment(AppModel.self) private var model

    private var settings: ScreenSaverSettings { model.screenSaver }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PopoverSection(L("Background")) {
                BackgroundControls(settings: settings,
                                   update: model.updateScreenSaver,
                                   onChoosePhoto: model.chooseScreenSaverBackgroundImage,
                                   onClearPhoto: model.clearScreenSaverBackgroundImage)
            }
            PopoverSection(L("Mascot")) {
                MascotControls(settings: settings, update: model.updateScreenSaver,
                               appSettings: model.appSettings,
                               updateApp: model.updateAppSettings)
            }
            PopoverSection(L("Widgets")) {
                WidgetToggles(settings: settings, update: model.updateScreenSaver)
            }
            PopoverSection(L("Layout & Position")) {
                SessionsCornerRow(settings: settings, update: model.updateScreenSaver)
                Footnote("Drag widgets on the screen saver to arrange and stack them.")
                WidgetLayoutResetButton(settings: settings, update: model.updateScreenSaver)
                    .font(.caption)
                if settings.showsSessions {
                    Footnote("Click a session chip on the screen saver to watch it live.")
                }
            }
            PopoverSection(L("Title")) {
                TitleControls(settings: settings, update: model.updateScreenSaver)
            }
            PopoverSection(L("Widget Size")) {
                WidgetSizeControls(settings: settings, update: model.updateScreenSaver)
            }
            PopoverSection(L("Display Dimming")) {
                DimmingControls(settings: settings, update: model.updateScreenSaver)
            }
            PopoverSection(L("Stays Bright")) {
                StayLitControls(settings: settings, update: model.updateScreenSaver)
            }
            Footnote("Tip: on the screen saver, swipe two fingers right to change dimming, or left to change what shows, and see the result right there.")
            PopoverSection(L("Activation Key")) {
                SettingRow("Start screen saver", systemImage: "keyboard") {
                    ShortcutRecorder(shortcut: settings.shortcut,
                                     onChange: { value in model.updateScreenSaver { $0.withShortcut(value) } },
                                     onRecordingChange: { model.setShortcutRecording($0) })
                }
                if let problem = model.shortcutProblem {
                    Footnote(problem, tone: Theme.warning)
                }
            }
            if settings.showsSessions, !model.sessions.board.sessions.isEmpty {
                PopoverSection(L("Pinned Sessions")) { pins }
            }
        }
    }

    /// Every running session, so one can be pinned before the screen saver starts.
    @ViewBuilder
    private var pins: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.sessions.board.sessions) { session in
                    Toggle(isOn: Binding(
                        get: { settings.isPinned(session.id) },
                        set: { value in model.updateScreenSaver { $0.pinning(session.id, value) } })) {
                        HStack(spacing: 6) {
                            Circle().fill(session.isWorking ? Theme.working : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(session.displayName).font(.caption).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .frame(maxHeight: 110)
        Footnote("Working sessions appear by themselves and fade out when they stop. Pinned ones stay.")
    }
}
