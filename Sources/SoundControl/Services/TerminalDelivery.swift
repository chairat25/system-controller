import AppKit

/// Types a line into the terminal that runs a given Claude Code process.
/// The process is matched by its tty, so the text always lands in the right tab.
/// tmux panes, iTerm2 and the macOS Terminal app are supported.
enum TerminalDelivery {
    static let itermBundleID = "com.googlecode.iterm2"
    static let terminalBundleID = "com.apple.Terminal"
    private static let tmuxFallbacks = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]

    private static let itermScript = """
    on run argv
        set targetTTY to item 1 of argv
        set lineText to item 2 of argv
        with timeout of 20 seconds
            tell application id "\(itermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTTY then
                                tell s to write text lineText
                                return "sent"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end timeout
        return "not-found"
    end run
    """

    /// `do script` in a tab whose program is running types the text and a return into that program.
    private static let terminalScript = """
    on run argv
        set targetTTY to item 1 of argv
        set lineText to item 2 of argv
        with timeout of 20 seconds
            tell application id "\(terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTTY then
                            do script lineText in t
                            return "sent"
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return "not-found"
    end run
    """

    /// tmux from the owner's own shell PATH, so any install location works; common locations as a fallback.
    static let tmuxPath: String? = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let found = run(shell, ["-lc", "command -v tmux"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           found.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: found) {
            return found
        }
        return tmuxFallbacks.first(where: FileManager.default.isExecutableFile(atPath:))
    }()

    /// True when the line was typed and submitted. Runs off the main thread.
    static func send(_ text: String, toProcess pid: Int32) async -> Bool {
        await Task.detached(priority: .utility) { sendBlocking(text, toProcess: pid) }.value
    }

    private static func sendBlocking(_ text: String, toProcess pid: Int32) -> Bool {
        guard let tty = tty(ofProcess: pid) else { return false }
        return sendToTmux(text, tty: tty)
            || sendByScript(itermScript, app: itermBundleID, text: text, tty: tty)
            || sendByScript(terminalScript, app: terminalBundleID, text: text, tty: tty)
    }

    static func tty(ofProcess pid: Int32) -> String? {
        guard let output = run("/bin/ps", ["-o", "tty=", "-p", String(pid)]) else { return nil }
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("?") else { return nil }
        return name.hasPrefix("/dev/") ? name : "/dev/\(name)"
    }

    private static func sendByScript(_ script: String, app bundleID: String, text: String, tty: String) -> Bool {
        guard AutomationAccess.isRunning(bundleID), AutomationAccess.isGranted(bundleID) else { return false }
        return run("/usr/bin/osascript", ["-e", script, tty, text])?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "sent"
    }

    /// The tmux binary and the pane whose pty is `tty`, when that terminal runs inside tmux.
    static func tmuxPane(forTTY tty: String) -> (tmux: String, pane: String)? {
        guard let tmux = tmuxPath,
              let panes = run(tmux, ["list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"]),
              let pane = panes.split(separator: "\n").compactMap({ line -> String? in
                  let parts = line.split(separator: " ")
                  return parts.count == 2 && String(parts[0]) == tty ? String(parts[1]) : nil
              }).first
        else { return nil }
        return (tmux, pane)
    }

    private static func sendToTmux(_ text: String, tty: String) -> Bool {
        guard let (tmux, pane) = tmuxPane(forTTY: tty) else { return false }
        return run(tmux, ["send-keys", "-t", pane, "-l", text]) != nil
            && run(tmux, ["send-keys", "-t", pane, "Enter"]) != nil
    }

    /// Standard output of a finished command, or nil when it could not start or exited with an error.
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
