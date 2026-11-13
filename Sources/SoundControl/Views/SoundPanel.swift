import SwiftUI
import SoundControlCore

/// Sound tab of the menu-bar popover: the sound engine, volume and pack, quick lock actions, and the latest events.
struct SoundPanel: View {
    @Environment(AppModel.self) private var model
    private static let recentCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            engine
            volumeAndPack
            QuickActions()
            recent
        }
    }

    private var engine: some View {
        let isOn = model.config.isListening
        let count = model.config.enabledTriggers.count
        return PopoverSection("Sound Engine") {
            HStack(spacing: Spacing.control) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundStyle(isOn ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound Control").font(.headline)
                    StatusIndicator(text: isOn ? "Listening · \(count) trigger\(count == 1 ? "" : "s") on" : "Paused",
                                    level: isOn ? .good : .off)
                }
                Spacer(minLength: Spacing.related)
                Toggle("Sound Control", isOn: Binding(get: { isOn },
                                                      set: { value in model.update { $0.withListening(value) } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
        }
    }

    private var volumeAndPack: some View {
        let volume = model.config.masterVolume
        return PopoverSection("Volume & Sound Pack") {
            HStack(spacing: Spacing.related) {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.rowIconWidth)
                Slider(value: Binding(get: { volume },
                                      set: { value in model.update { $0.withMasterVolume(value) } }), in: 0...1)
                    .tint(Theme.accent)
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            SettingRow("Pack", systemImage: "square.stack.3d.up") {
                Picker("Pack", selection: Binding(get: { model.config.activePack },
                                                  set: { value in model.update { $0.selectingPack(value) } })) {
                    ForEach(BuiltInPack.allCases, id: \.self) { Text($0.title).tag(PackSelection.builtIn($0)) }
                    if !model.config.customPacks.isEmpty {
                        Divider()
                        ForEach(model.config.customPacks) { Text($0.name).tag(PackSelection.custom($0.id)) }
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var recent: some View {
        PopoverSection("Recent Activity") {
            if model.log.entries.count > Self.recentCount {
                OpenWindowLink(title: "Show all")
            }
        } content: {
            if model.log.entries.isEmpty {
                Footnote("No events yet. Plug in the charger or lock the screen to hear one.")
            } else {
                VStack(spacing: Spacing.related) {
                    ForEach(model.log.entries.prefix(Self.recentCount)) { entry in
                        EventListItem(entry: entry)
                    }
                }
            }
        }
    }
}

/// Utility actions that lock the keyboard. Explains the Accessibility permission when macOS refuses it.
private struct QuickActions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isLocked = model.keyboardLock.isLocked
        PopoverSection("Quick Actions") {
            if isLocked {
                StatusIndicator(text: "Locked", level: .pending)
            }
        } content: {
            SecondaryActionButton(title: "Lock keyboard for cleaning", systemImage: "keyboard.badge.ellipsis",
                                  isDisabled: isLocked) { model.keyboardLock.lockKeyboard() }
            SecondaryActionButton(title: "Lock for owner (screen stays on)", systemImage: "touchid",
                                  isDisabled: isLocked) { model.lockForOwner() }
            if let problem = model.keyboardLock.problem {
                Footnote(problem, tone: Theme.warning)
                Button("Open Accessibility Settings") { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
        }
    }
}

/// One sound event: what happened, which sound played or why it was skipped, and when.
struct EventListItem: View {
    let entry: ActivityEntry

    var body: some View {
        let info = TriggerCatalog.info(for: entry.trigger)
        HStack(spacing: Spacing.related) {
            SymbolTile(symbol: info.symbol, isActive: entry.didPlay, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title).font(.callout).lineLimit(1)
                outcome
            }
            Spacer(minLength: Spacing.related)
            Text(entry.date, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .opacity(entry.didPlay ? 1 : 0.75)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var outcome: some View {
        if let reason = entry.skipReason {
            Label(withContext("Skipped · \(reason.rawValue)"), systemImage: "forward.end")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Label(withContext(entry.soundName ?? "Sound"), systemImage: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func withContext(_ outcome: String) -> String {
        guard let context = entry.context, !context.isEmpty else { return outcome }
        return "\(context) · \(outcome)"
    }
}

/// Opens the full Sound Control window, where every event, trigger and pack lives.
struct OpenWindowLink: View {
    @Environment(\.openWindow) private var openWindow
    let title: String

    var body: some View {
        Button(title) {
            openWindow(id: "main")
            NSApp.activate()
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}
