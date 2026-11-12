import SwiftUI
import SoundControlCore

/// Sound Control tab of the menu-bar popover: quick controls and the latest events.
struct SoundPanel: View {
    @Environment(AppModel.self) private var model
    private static let recentCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sound Control").font(.headline)
                    Text("\(model.config.enabledTriggers.count) triggers on").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.config.isListening },
                                         set: { value in model.update { $0.withListening(value) } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.config.masterVolume },
                                      set: { value in model.update { $0.withMasterVolume(value) } }), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            Picker("Pack", selection: Binding(get: { model.config.activePack },
                                              set: { value in model.update { $0.selectingPack(value) } })) {
                ForEach(BuiltInPack.allCases, id: \.self) { Text($0.title).tag(PackSelection.builtIn($0)) }
                if !model.config.customPacks.isEmpty {
                    Divider()
                    ForEach(model.config.customPacks) { Text($0.name).tag(PackSelection.custom($0.id)) }
                }
            }

            KeyboardLockRow()

            Divider()
            Text("RECENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if model.log.entries.isEmpty {
                Text("No events yet").font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(model.log.entries.prefix(Self.recentCount)) { entry in
                    ActivityRow(entry: entry, compact: true)
                }
            }
        }
    }
}

/// Starts a keyboard lock: the cleaning lock (hold to unlock) or the owner lock (Touch ID / password).
/// Explains the Accessibility permission when macOS refuses it.
private struct KeyboardLockRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            lockButton("Lock keyboard for cleaning", systemImage: "keyboard.badge.ellipsis") {
                model.keyboardLock.lockKeyboard()
            }
            lockButton("Lock for owner (screen stays on)", systemImage: "touchid") {
                model.lockForOwner()
            }
            if let problem = model.keyboardLock.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
                Button("Open Accessibility Settings") { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
        }
    }

    private func lockButton(_ title: String, systemImage: String, start: @escaping () -> Void) -> some View {
        Button(action: start) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(model.keyboardLock.isLocked)
    }
}
