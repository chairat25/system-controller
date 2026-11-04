import SwiftUI
import SoundControlCore

/// Dev tab of the menu-bar popover: Claude Code settings that the Stop hook reads.
struct DevPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto /compact when idle", isOn: Binding(
                get: { model.idleCompact.isEnabled },
                set: { value in model.updateIdleCompact { $0.withEnabled(value) } }))
            Stepper(value: Binding(
                get: { model.idleCompact.idleMinutes },
                set: { value in model.updateIdleCompact { $0.withIdleMinutes(value) } }),
                    in: IdleCompactSettings.minimumMinutes...IdleCompactSettings.maximumMinutes) {
                LabeledContent("Idle time", value: "\(model.idleCompact.idleMinutes) min")
            }
            .disabled(!model.idleCompact.isEnabled)
            Text("Sends /compact to the iTerm2 session that has been idle that long. Applies from the next Claude reply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
