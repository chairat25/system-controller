import SwiftUI
import SoundControlCore

/// The Screen Saver tab's settings page: dimming, what stays lit, the start shortcut and pinned sessions.
struct ScreenSaverSettingsPage: View {
    @Environment(AppModel.self) private var model

    private static let dimAfterChoices = [10, 30, 60, 120, 300, 600, 1800, 3600]
    private static let fadeChoices = [0, 1, 3, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
    private static let litRange: ClosedRange<Double> = 0.05...1

    private var settings: ScreenSaverSettings { model.screenSaver }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIMMING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Toggle("Dim automatically", isOn: Binding(
                get: { settings.isDimEnabled },
                set: { value in model.updateScreenSaver { $0.withDimEnabled(value) } }))
            dimControls.disabled(!settings.isDimEnabled)
            litControls

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

            if settings.showsSessions, !model.sessions.board.sessions.isEmpty {
                Divider()
                pins
            }
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
    }

    /// What stays lit while the rest dims, each at its own brightness.
    @ViewBuilder
    private var litControls: some View {
        Text("STAY LIT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        litControl("Clock", isOn: settings.isClockBright, level: settings.clockLevel,
                   setOn: { value in model.updateScreenSaver { $0.withClockBright(value) } },
                   setLevel: { value in model.updateScreenSaver { $0.withClockLevel(value) } })
        if settings.mascot != .none {
            litControl(settings.mascot.title, isOn: settings.isMascotBright, level: settings.mascotLevel,
                       setOn: { value in model.updateScreenSaver { $0.withMascotBright(value) } },
                       setLevel: { value in model.updateScreenSaver { $0.withMascotLevel(value) } })
        }
        Text("Ticked items keep this brightness while the rest of the screen dims.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func litControl(_ title: String, isOn: Bool, level: Double,
                            setOn: @escaping (Bool) -> Void, setLevel: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isOn }, set: setOn)) {
                LabeledContent(title, value: "\(Int((level * 100).rounded()))%")
            }
            Slider(value: Binding(get: { level }, set: setLevel), in: Self.litRange)
                .disabled(!isOn)
        }
    }

    /// Every running session, so one can be pinned before the screen saver starts.
    @ViewBuilder
    private var pins: some View {
        Text("PINNED SESSIONS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
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
        Text("Working sessions appear by themselves and fade out when they stop. Pinned ones stay.")
            .font(.caption).foregroundStyle(.secondary)
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
