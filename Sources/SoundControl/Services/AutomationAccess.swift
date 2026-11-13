import AppKit
import Carbon.HIToolbox

/// The permission macOS asks for before this app may type into or read a terminal (Privacy & Security > Automation).
/// It is requested as soon as the app starts, and again when a terminal app opens later, so nothing waits for the
/// moment a handoff has to be sent.
enum AutomationAccess {
    enum State: Equatable {
        case granted, denied, notRunning, unknown
    }

    struct Terminal: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static let terminals = [
        Terminal(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        Terminal(bundleID: "com.apple.Terminal", name: "Terminal")
    ]

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Checks whether Automation permission is already granted without showing a macOS consent prompt.
    static func isGranted(_ bundleID: String) -> Bool {
        permissionState(bundleID, askUser: false) == .granted
    }

    /// Shows the macOS consent prompt when it has not been answered yet. Blocks while the prompt is up, so it runs off the main thread.
    static func request(_ bundleID: String) async -> State {
        await Task.detached(priority: .utility) {
            permissionState(bundleID, askUser: true)
        }.value
    }

    private static func permissionState(_ bundleID: String, askUser: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let address = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askUser)
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventNotPermitted: return .denied
        case procNotFound: return .notRunning
        default: return .unknown
        }
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        if let url { NSWorkspace.shared.open(url) }
    }
}
