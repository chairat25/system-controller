import SwiftUI
import SoundControlCore

/// Dev tab of the menu-bar popover: what the app does to the Claude Code sessions on this Mac.
struct DevPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            idleCompact
            Divider()
            limitGuard
            Divider()
            terminalAccess
        }
    }

    private var idleCompact: some View {
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
            if let note = model.sessions.idleNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Text(model.sessions.hasIdleCompactHook
                 ? "Your Claude Code Stop hook sends this /compact, so the app leaves it to the hook."
                 : "Sends /compact to a session that finished a reply and then sat idle that long.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var limitGuard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("5-HOUR LIMIT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Toggle("Hand off and /compact near the limit", isOn: Binding(
                get: { model.limitGuardSettings.isEnabled },
                set: { value in model.updateLimitGuard { $0.withEnabled(value) } }))
            Stepper(value: Binding(
                get: { model.limitGuardSettings.thresholdPercent },
                set: { value in model.updateLimitGuard { $0.withThreshold(percent: value) } }),
                    in: LimitGuardSettings.minimumPercent...LimitGuardSettings.maximumPercent) {
                LabeledContent("Act when left", value: "\(model.limitGuardSettings.thresholdPercent)%")
            }
            .disabled(!model.limitGuardSettings.isEnabled)
            quotaStatus
            if let note = model.sessions.guardNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Text("Every working Claude session is asked to write a handoff note, then gets /compact once it stops. Idle sessions are left alone.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quotaStatus: some View {
        if let quota = model.sessions.quota {
            LabeledContent("Window left", value: "\(Int(quota.remainingPercent.rounded()))% · resets \(quota.resetsAt.formatted(.dateTime.hour().minute()))")
        } else {
            Text(model.sessions.quotaProblem ?? "Reading usage…")
                .font(.caption).foregroundStyle(model.sessions.quotaProblem == nil ? Color.secondary : Theme.warning)
        }
    }

    /// Typing into and reading terminals needs the Automation permission, asked for when the app starts.
    private var terminalAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TERMINALS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            ForEach(model.terminalPermissions.installed) { terminal in
                LabeledContent(terminal.name) {
                    Text(Self.label(model.terminalPermissions.states[terminal.bundleID] ?? .notRunning))
                        .font(.caption)
                        .foregroundStyle(model.terminalPermissions.states[terminal.bundleID] == .denied ? Theme.warning : .secondary)
                }
            }
            if let hasTmux = model.terminalPermissions.hasTmux {
                LabeledContent("tmux", value: hasTmux ? "Ready" : "Not installed")
            }
            HStack {
                Button("Check again") { model.terminalPermissions.refresh() }
                if model.terminalPermissions.hasDenied {
                    Button("Open Automation Settings") { AutomationAccess.openSettings() }
                }
            }
            .font(.caption)
            Text("Other terminals (Ghostty, Warp…) cannot be typed into, so they only show the transcript feed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func label(_ state: AutomationAccess.State) -> String {
        switch state {
        case .granted: "Allowed"
        case .denied: "Blocked: allow it in Automation settings"
        case .notRunning: "Asked when it opens"
        case .unknown: "Not answered yet"
        }
    }
}
