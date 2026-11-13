import SwiftUI
import SoundControlCore

/// Developer tab of the menu-bar popover: what the app does to the Claude Code sessions on this Mac,
/// split into automation, usage, terminal access and diagnostics.
struct DevPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            automation
            usage
            terminalAccess
            diagnostics
        }
    }

    private var automation: some View {
        PopoverSection("Automation") {
            SettingToggle(title: "Auto /compact when idle", systemImage: "arrow.down.right.and.arrow.up.left",
                          isOn: model.idleCompact.isEnabled,
                          onChange: { value in model.updateIdleCompact { $0.withEnabled(value) } })
            Stepper(value: Binding(
                get: { model.idleCompact.idleMinutes },
                set: { value in model.updateIdleCompact { $0.withIdleMinutes(value) } }),
                    in: IdleCompactSettings.minimumMinutes...IdleCompactSettings.maximumMinutes) {
                SettingRow("Idle time", systemImage: "timer") {
                    Text("\(model.idleCompact.idleMinutes) min").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .disabled(!model.idleCompact.isEnabled)
            if let note = model.sessions.idleNote {
                Footnote(note)
            }
            Footnote(model.sessions.hasIdleCompactHook
                     ? "Your Claude Code Stop hook sends this /compact, so the app leaves it to the hook."
                     : "Sends /compact to a session that finished a reply and then sat idle that long.")
        }
    }

    private var usage: some View {
        PopoverSection("Session & Usage") {
            quotaStatus
            Divider()
            SettingToggle(title: "Hand off and /compact near the limit", systemImage: "arrow.triangle.branch",
                          isOn: model.limitGuardSettings.isEnabled,
                          onChange: { value in model.updateLimitGuard { $0.withEnabled(value) } })
            Stepper(value: Binding(
                get: { model.limitGuardSettings.thresholdPercent },
                set: { value in model.updateLimitGuard { $0.withThreshold(percent: value) } }),
                    in: LimitGuardSettings.minimumPercent...LimitGuardSettings.maximumPercent) {
                SettingRow("Act when left", systemImage: "gauge.with.dots.needle.33percent") {
                    Text("\(model.limitGuardSettings.thresholdPercent)%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .disabled(!model.limitGuardSettings.isEnabled)
            if let note = model.sessions.guardNote {
                Footnote(note)
            }
            Footnote("Every working Claude session is asked to write a handoff note, then gets /compact once it stops. Idle sessions are left alone.")
        }
    }

    /// The current 5-hour window, read from the account: status, not a setting.
    @ViewBuilder
    private var quotaStatus: some View {
        if let quota = model.sessions.quota {
            let percent = Int(quota.remainingPercent.rounded())
            VStack(alignment: .leading, spacing: Spacing.micro) {
                HStack {
                    Text("5-hour window").font(.callout)
                    Spacer()
                    Text("\(percent)% left").font(.callout.monospacedDigit().weight(.medium))
                }
                ProgressView(value: quota.remainingPercent, total: 100)
                    .tint(percent <= model.limitGuardSettings.thresholdPercent ? Theme.warning : Theme.accent)
                Text("Resets at \(quota.resetsAt.formatted(.dateTime.hour().minute()))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        } else if let problem = model.sessions.quotaProblem {
            StatusIndicator(text: problem, level: .pending)
        } else {
            StatusIndicator(text: "Reading usage…", level: .off)
        }
    }

    /// Typing into and reading terminals needs the Automation permission, asked for when the app starts.
    private var terminalAccess: some View {
        PopoverSection("Terminal Access") {
            ForEach(model.terminalPermissions.installed) { terminal in
                let state = model.terminalPermissions.states[terminal.bundleID] ?? .notRunning
                SettingRow(terminal.name, systemImage: "apple.terminal") {
                    StatusIndicator(text: Self.label(state), level: Self.level(state))
                }
            }
            if let hasTmux = model.terminalPermissions.hasTmux {
                SettingRow("tmux", systemImage: "square.split.2x1") {
                    StatusIndicator(text: hasTmux ? "Ready" : "Unavailable", level: hasTmux ? .good : .off)
                }
            }
            SettingRow("Other terminals", detail: "Ghostty, Warp…: transcript feed only", systemImage: "questionmark.app") {
                StatusIndicator(text: "Unsupported", level: .off)
            }
        }
    }

    private var diagnostics: some View {
        PopoverSection("Diagnostics") {
            HStack {
                Button("Check again") { model.terminalPermissions.refresh() }
                if model.terminalPermissions.hasDenied {
                    Button("Open Automation Settings") { AutomationAccess.openSettings() }
                }
                Spacer()
            }
            .controlSize(.small)
            Footnote(diagnosticResult)
        }
    }

    private var diagnosticResult: String {
        let permissions = model.terminalPermissions
        let result = permissions.hasDenied ? "A terminal is blocked in Automation settings." : "No terminal is blocked."
        guard let checked = permissions.lastChecked else { return result }
        return "\(result) Last checked \(checked.formatted(.dateTime.hour().minute().second()))."
    }

    private static func label(_ state: AutomationAccess.State) -> String {
        switch state {
        case .granted: "Allowed"
        case .denied: "Blocked"
        case .notRunning: "Asked when it opens"
        case .unknown: "Pending Permission"
        }
    }

    private static func level(_ state: AutomationAccess.State) -> StatusLevel {
        switch state {
        case .granted: .good
        case .denied: .problem
        case .notRunning: .off
        case .unknown: .pending
        }
    }
}
