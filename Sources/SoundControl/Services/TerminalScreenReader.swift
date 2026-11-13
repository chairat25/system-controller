import AppKit
import SoundControlCore

/// Reads what a Claude Code terminal is showing right now, so the screen saver can mirror it as it streams in.
/// Terminals are matched by tty, like `TerminalDelivery`. tmux panes are read directly, iTerm2 and Terminal tabs
/// through one AppleScript call per app for all of them. Anything else simply gives no text and the caller falls back to the transcript.
enum TerminalScreenReader {
    private static let itermScript = """
    on run argv
        set recordSeparator to character id \(TerminalScreen.recordSeparator.asciiValue ?? 30)
        set unitSeparator to character id \(TerminalScreen.unitSeparator.asciiValue ?? 31)
        set output to ""
        with timeout of 10 seconds
            tell application id "\(TerminalDelivery.itermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sessionTTY to tty of s
                            if argv contains sessionTTY then
                                set output to output & sessionTTY & recordSeparator & (contents of s) & unitSeparator
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end timeout
        return output
    end run
    """

    private static let terminalScript = """
    on run argv
        set recordSeparator to character id \(TerminalScreen.recordSeparator.asciiValue ?? 30)
        set unitSeparator to character id \(TerminalScreen.unitSeparator.asciiValue ?? 31)
        set output to ""
        with timeout of 10 seconds
            tell application id "\(TerminalDelivery.terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabTTY to tty of t
                        if argv contains tabTTY then
                            set output to output & tabTTY & recordSeparator & (contents of t) & unitSeparator
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return output
    end run
    """

    /// The screen text of each process's terminal, keyed by pid. Runs off the main thread.
    static func capture(processes: [Int32]) async -> [Int32: String] {
        await Task.detached(priority: .utility) { captureBlocking(processes) }.value
    }

    private static func captureBlocking(_ processes: [Int32]) -> [Int32: String] {
        let ttys = Dictionary(processes.compactMap { pid in
            TerminalDelivery.tty(ofProcess: pid).map { ($0, pid) }
        }, uniquingKeysWith: { first, _ in first })
        var screens: [Int32: String] = [:]
        var remaining: [String] = []
        for (tty, pid) in ttys {
            if let (tmux, pane) = TerminalDelivery.tmuxPane(forTTY: tty),
               let text = TerminalDelivery.run(tmux, ["capture-pane", "-p", "-t", pane]) {
                screens[pid] = text
            } else {
                remaining.append(tty)
            }
        }
        for (script, app) in [(itermScript, TerminalDelivery.itermBundleID), (terminalScript, TerminalDelivery.terminalBundleID)] {
            let missing = remaining.filter { tty in ttys[tty].map { screens[$0] == nil } ?? false }
            for (tty, text) in capture(missing, script: script, app: app) {
                if let pid = ttys[tty] { screens[pid] = text }
            }
        }
        return screens
    }

    private static func capture(_ ttys: [String], script: String, app bundleID: String) -> [String: String] {
        guard !ttys.isEmpty,
              AutomationAccess.isRunning(bundleID),
              AutomationAccess.isGranted(bundleID),
              let output = TerminalDelivery.run("/usr/bin/osascript", ["-e", script] + ttys)
        else { return [:] }
        return TerminalScreen.parseCaptures(output)
    }
}
