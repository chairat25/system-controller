import SwiftUI
import SoundControlCore

/// Screen Saver tab of the menu-bar popover: what the Smartheart Screen Saver shows and how it dims.
struct ScreenSaverPanel: View {
    @Environment(AppModel.self) private var model

    private static let dimAfterChoices = [10, 30, 60, 120, 300, 600, 1800, 3600]
    private static let fadeChoices = [0, 1, 3, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    private var settings: ScreenSaverSettings { model.screenSaver }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("SHOW").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            widgetToggle("Clock", systemImage: "clock", widget: .clock)
            widgetToggle("Calendar", systemImage: "calendar", widget: .calendar)
            widgetToggle("Claude usage", systemImage: "sparkle", widget: .claudeUsage)
            sessionsSection

            Divider()
            Text("DIMMING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Toggle("Dim automatically", isOn: Binding(
                get: { settings.isDimEnabled },
                set: { value in model.updateScreenSaver { $0.withDimEnabled(value) } }))
            dimControls.disabled(!settings.isDimEnabled)

            Divider()
            Text("SHORTCUT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            LabeledContent("Start screen saver") {
                ShortcutRecorder(shortcut: settings.shortcut,
                                 onChange: { value in model.updateScreenSaver { $0.withShortcut(value) } },
                                 onRecordingChange: { model.setShortcutRecording($0) })
            }
            if let problem = model.shortcutProblem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
            }

            Divider()
            Button {
                model.lockForOwner()
            } label: {
                Label("Start screen saver", systemImage: "touchid").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.keyboardLock.isLocked)
            if let problem = model.keyboardLock.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
                Button("Open Accessibility Settings") { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
            Text("Keys stay blocked and only your fingerprint or password gets you back in. Move the mouse to wake a dimmed screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "heart.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Smartheart Screen Saver").font(.headline)
                Text("\(settings.widgets.count) of \(ScreenSaverWidget.allCases.count) widgets on")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func widgetToggle(_ title: String, systemImage: String, widget: ScreenSaverWidget) -> some View {
        Toggle(isOn: Binding(get: { settings.shows(widget) },
                             set: { value in model.updateScreenSaver { $0.showing(widget, value) } })) {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var dimControls: some View {
        Picker("Start after", selection: Binding(
            get: { settings.dimAfterSeconds },
            set: { value in model.updateScreenSaver { $0.withDimAfter(seconds: value) } })) {
            ForEach(Self.choices(Self.dimAfterChoices, including: settings.dimAfterSeconds), id: \.self) {
                Text(Self.duration($0))
            }
        }
        Picker("Fade over", selection: Binding(
            get: { settings.fadeSeconds },
            set: { value in model.updateScreenSaver { $0.withFade(seconds: value) } })) {
            ForEach(Self.choices(Self.fadeChoices, including: settings.fadeSeconds), id: \.self) {
                Text($0 == 0 ? "Instantly" : Self.duration($0))
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Dim to", value: Self.levelLabel(settings.dimLevel))
            Slider(value: Binding(
                get: { settings.dimLevel },
                set: { value in model.updateScreenSaver { $0.withDimLevel(value) } }), in: 0...1)
        }
        Toggle("Bright clock only", isOn: Binding(
            get: { settings.isClockBright },
            set: { value in model.updateScreenSaver { $0.withClockBright(value) } }))
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Clock brightness", value: "\(Int((settings.clockLevel * 100).rounded()))%")
            Slider(value: Binding(
                get: { settings.clockLevel },
                set: { value in model.updateScreenSaver { $0.withClockLevel(value) } }), in: 0.05...1)
        }
        .disabled(!settings.isClockBright)
    }

    /// Switch for the corner list, plus every running session so one can be pinned before the screen saver starts.
    @ViewBuilder
    private var sessionsSection: some View {
        Toggle(isOn: Binding(get: { settings.showsSessions },
                             set: { value in model.updateScreenSaver { $0.withShowsSessions(value) } })) {
            Label("Claude sessions", systemImage: "terminal")
        }
        if settings.showsSessions {
            LabeledContent("Position") {
                CornerPicker(selection: settings.sessionsCorner,
                             onSelect: { corner in model.updateScreenSaver { $0.withSessionsCorner(corner) } })
            }
        }
        if settings.showsSessions, !model.sessions.board.sessions.isEmpty {
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
            Text("Working sessions show a green dot in the chosen corner and fade out when they stop. Tick one to pin it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The presets plus the saved value, so a custom value from the settings file still shows.
    private static func choices(_ presets: [Int], including current: Int) -> [Int] {
        presets.contains(current) ? presets : (presets + [current]).sorted()
    }

    private static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min"
    }

    private static func levelLabel(_ level: Double) -> String {
        level == 0 ? "No light" : "\(Int((level * 100).rounded()))%"
    }
}
