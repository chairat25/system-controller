import AppKit
import Observation

/// Keeps the Automation permission for each terminal app requested and its answer known.
/// Asks once at launch for the terminals that are open, and again whenever one opens later.
@MainActor
@Observable
final class TerminalPermissions {
    private(set) var states: [String: AutomationAccess.State] = [:]
    /// Nil until looked up; finding tmux runs the login shell, so it happens off the main thread.
    private(set) var hasTmux: Bool?
    /// When the owner last pressed Check again; nil until then.
    private(set) var lastChecked: Date?

    @ObservationIgnored private var launchObserver: NSObjectProtocol?
    @ObservationIgnored private var isLocked: @MainActor () -> Bool = { false }

    /// Terminals installed on this Mac, the only ones worth showing.
    var installed: [AutomationAccess.Terminal] {
        AutomationAccess.terminals.filter { AutomationAccess.isInstalled($0.bundleID) }
    }

    var hasDenied: Bool { states.values.contains(.denied) }

    func start(isLocked: @escaping @MainActor () -> Bool = { false }) {
        self.isLocked = isLocked
        guard launchObserver == nil else { return }
        AutomationAccess.terminals.forEach(request)
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { TerminalDelivery.tmuxPath != nil }.value
            self?.hasTmux = found
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier,
                  let terminal = AutomationAccess.terminals.first(where: { $0.bundleID == bundleID }) else { return }
            MainActor.assumeIsolated { self?.request(terminal) }
        }
    }

    /// Checks again, for example after the owner changed the setting in System Settings.
    func refresh() {
        AutomationAccess.terminals.forEach(request)
        lastChecked = Date()
    }

    private func request(_ terminal: AutomationAccess.Terminal) {
        guard !isLocked() else { return }
        guard AutomationAccess.isRunning(terminal.bundleID) else {
            set(states[terminal.bundleID] == .granted ? .granted : .notRunning, for: terminal.bundleID)
            return
        }
        Task { [weak self] in
            let state = await AutomationAccess.request(terminal.bundleID)
            self?.set(state, for: terminal.bundleID)
        }
    }

    /// Every write redraws the readers, so an unchanged answer is not written again.
    private func set(_ state: AutomationAccess.State, for bundleID: String) {
        if states[bundleID] != state { states[bundleID] = state }
    }
}
