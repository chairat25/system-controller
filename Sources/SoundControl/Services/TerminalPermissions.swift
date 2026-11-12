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

    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// Terminals installed on this Mac, the only ones worth showing.
    var installed: [AutomationAccess.Terminal] {
        AutomationAccess.terminals.filter { AutomationAccess.isInstalled($0.bundleID) }
    }

    var hasDenied: Bool { states.values.contains(.denied) }

    func start() {
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
    }

    private func request(_ terminal: AutomationAccess.Terminal) {
        guard AutomationAccess.isRunning(terminal.bundleID) else {
            states[terminal.bundleID] = states[terminal.bundleID] == .granted ? .granted : .notRunning
            return
        }
        Task { [weak self] in
            let state = await AutomationAccess.request(terminal.bundleID)
            self?.states[terminal.bundleID] = state
        }
    }
}
