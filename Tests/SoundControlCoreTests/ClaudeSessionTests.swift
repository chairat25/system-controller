import Foundation
import Testing
@testable import SoundControlCore

private func session(_ id: String, working: Bool, name: String? = nil) -> ClaudeSession {
    ClaudeSession(id: id, pid: 100, name: name ?? id, cwd: "/tmp/\(id)", isWorking: working,
                  statusUpdatedAt: Date(timeIntervalSince1970: 0))
}

@Suite("Claude session files")
struct ClaudeSessionParseTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("reads name, pid and a busy status as working")
    func busy() throws {
        let parsed = try #require(ClaudeSession.parse(data("""
        {"pid":42,"sessionId":"abc","cwd":"/Users/me/app","name":"app-1","kind":"interactive",
         "status":"busy","statusUpdatedAt":1794385963996}
        """)))
        #expect(parsed.id == "abc")
        #expect(parsed.pid == 42)
        #expect(parsed.name == "app-1")
        #expect(parsed.isWorking)
        #expect(parsed.statusUpdatedAt == Date(timeIntervalSince1970: 1_794_385_963.996))
    }

    @Test("idle and shell are not working")
    func notWorking() throws {
        for status in ["idle", "shell", "waiting"] {
            let parsed = try #require(ClaudeSession.parse(data(
                #"{"pid":1,"sessionId":"a","cwd":"/x","status":"\#(status)"}"#)))
            #expect(!parsed.isWorking)
        }
    }

    @Test("falls back to the folder name when the session has no name")
    func nameFallback() throws {
        let parsed = try #require(ClaudeSession.parse(data(#"{"pid":1,"sessionId":"a","cwd":"/Users/me/my-app"}"#)))
        #expect(parsed.name == "my-app")
    }

    @Test("skips non-interactive sessions and broken files")
    func skips() {
        #expect(ClaudeSession.parse(data(#"{"pid":1,"sessionId":"a","cwd":"/x","kind":"sdk"}"#)) == nil)
        #expect(ClaudeSession.parse(data(#"{"sessionId":"a","cwd":"/x"}"#)) == nil)
        #expect(ClaudeSession.parse(data("not json")) == nil)
    }
}

@Suite("Same conversation in two terminals")
struct ClaudeSessionCollapseTests {
    private func copy(pid: Int32, working: Bool, updated: TimeInterval) -> ClaudeSession {
        ClaudeSession(id: "same", pid: pid, name: "genie", cwd: "/x", isWorking: working,
                      statusUpdatedAt: Date(timeIntervalSince1970: updated))
    }

    @Test("two processes of one conversation become one session")
    func one() {
        let result = ClaudeSession.collapsed([copy(pid: 1, working: false, updated: 10),
                                              copy(pid: 2, working: false, updated: 20)])
        #expect(result.map(\.pid) == [2])
    }

    @Test("the working copy wins even when the other moved later")
    func workingWins() {
        let result = ClaudeSession.collapsed([copy(pid: 1, working: true, updated: 10),
                                              copy(pid: 2, working: false, updated: 99)])
        #expect(result.map(\.pid) == [1])
    }

    @Test("different conversations are all kept")
    func distinct() {
        let result = ClaudeSession.collapsed([session("a", working: true), session("b", working: false)])
        #expect(Set(result.map(\.id)) == ["a", "b"])
    }
}

@Suite("Claude transcript")
struct ClaudeTranscriptTests {
    private func tail(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }
    private func user(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }
    private func assistant(_ blocks: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[\#(blocks)]}}"#
    }

    @Test("takes the newest ai-title, Thai included")
    func newestTitle() {
        let digest = ClaudeTranscript.digest(inTail: tail([
            #"{"type":"ai-title","aiTitle":"Old topic"}"#,
            user("hello"),
            #"{"type":"ai-title","aiTitle":"การอนุมัติคำสั่งซื้อผ่าน Genie"}"#,
            #"{"type":"last-prompt"}"#]))
        #expect(digest.aiTitle == "การอนุมัติคำสั่งซื้อผ่าน Genie")
        #expect(digest.title == "การอนุมัติคำสั่งซื้อผ่าน Genie")
    }

    @Test("without an ai-title the latest prompt names the session")
    func promptFallback() {
        let digest = ClaudeTranscript.digest(inTail: tail([user("first"), user("ขอทดสอบนิดนึงนะ")]))
        #expect(digest.aiTitle == nil)
        #expect(digest.title == "ขอทดสอบนิดนึงนะ")
    }

    @Test("a long prompt is shortened to a title")
    func longPrompt() {
        let digest = ClaudeTranscript.digest(inTail: tail([user(String(repeating: "word ", count: 40))]))
        #expect((digest.title ?? "").count == ClaudeTranscript.titleLength)
        #expect(digest.title?.hasSuffix("…") == true)
    }

    @Test("activity lists prompts, replies and tool calls, oldest first")
    func activity() {
        let digest = ClaudeTranscript.digest(inTail: tail([
            user("fix the bug"),
            assistant(#"{"type":"text","text":"Looking now"},{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}"#),
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"files"}]}}"#,
            assistant(#"{"type":"text","text":"Done"}"#)]))
        #expect(digest.activity == [
            TranscriptLine(kind: .user, text: "fix the bug"),
            TranscriptLine(kind: .assistant, text: "Looking now"),
            TranscriptLine(kind: .tool, text: "Bash  ls -la"),
            TranscriptLine(kind: .assistant, text: "Done")])
    }

    @Test("keeps only the newest lines")
    func limit() {
        let lines = (1...9).map { user("message \($0)") }
        let digest = ClaudeTranscript.digest(inTail: tail(lines), activityLimit: 3)
        #expect(digest.activity.map(\.text) == ["message 7", "message 8", "message 9"])
    }

    @Test("a run of tool calls does not push the reply off the feed")
    func toolBudget() {
        let tools = (1...8).map { assistant(#"{"type":"tool_use","name":"Bash","input":{"command":"echo \#($0)"}}"#) }
        let digest = ClaudeTranscript.digest(inTail: tail([assistant(#"{"type":"text","text":"My reply"}"#)] + tools))
        let kinds = digest.activity.map(\.kind)
        #expect(kinds.contains(.assistant))
        #expect(kinds.filter { $0 == .tool }.count == 3)
        #expect(digest.activity.last?.text == "Bash  echo 8")
    }

    @Test("a tool shows its description, or the first line of a long command")
    func toolDetail() {
        let described = assistant(#"{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"List files"}}"#)
        let multiline = assistant(#"{"type":"tool_use","name":"Bash","input":{"command":"python3 - <<'E'\nprint(1)\nE"}}"#)
        #expect(ClaudeTranscript.digest(inTail: tail([described])).activity.first?.text == "Bash  List files")
        #expect(ClaudeTranscript.digest(inTail: tail([multiline])).activity.first?.text == "Bash  python3 - <<'E'")
    }

    @Test("skips thinking, system text, meta and sub-agent lines")
    func skips() {
        let digest = ClaudeTranscript.digest(inTail: tail([
            user("real"),
            user("<system-reminder>noise</system-reminder>"),
            #"{"type":"user","isMeta":true,"message":{"content":"meta"}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"agent"}]}}"#,
            assistant(#"{"type":"thinking","thinking":"hmm"}"#)]))
        #expect(digest.activity == [TranscriptLine(kind: .user, text: "real")])
    }

    @Test("collapses whitespace, and survives a cut first line and garbage")
    func tidy() {
        let digest = ClaudeTranscript.digest(inTail: tail([
            #"ut":"cut off"}"#, "not json", assistant(#"{"type":"text","text":"a\n\n  b"}"#)]))
        #expect(digest.activity == [TranscriptLine(kind: .assistant, text: "a b")])
        #expect(ClaudeTranscript.digest(inTail: Data()) == .empty)
    }

    @Test("a session shows its title, or its name until one is known")
    func displayName() {
        let plain = session("a", working: true, name: "genie-1")
        #expect(plain.displayName == "genie-1")
        #expect(plain.withTitle("Fix export").displayName == "Fix export")
        #expect(plain.withTitle("Fix export").withTitle(nil).displayName == "genie-1")
    }
}

@Suite("Session activity window")
struct ClaudeSessionActivityTests {
    @Test("active while working and for the grace period after the last status change")
    func window() {
        let now = Date(timeIntervalSince1970: 1_000)
        func make(working: Bool, ago: TimeInterval) -> ClaudeSession {
            ClaudeSession(id: "a", pid: 1, name: "a", cwd: "/a", isWorking: working,
                          statusUpdatedAt: now.addingTimeInterval(-ago))
        }
        #expect(make(working: true, ago: 600).isActive(now: now, grace: 15))
        #expect(make(working: false, ago: 5).isActive(now: now, grace: 15))
        #expect(!make(working: false, ago: 30).isActive(now: now, grace: 15))
    }
}

@Suite("Terminal screen")
struct TerminalScreenTests {
    private let rule = String(repeating: "─", count: 40)

    private var screen: String {
        ["● Here is the answer", "", "  ⎿  Read file", "", "✽ Nesting… (45s · ↓ 3.9k tokens)", " ",
         rule, "❯ ", rule, "  Sonnet 5.5 | high | 22%", "  ⏵⏵ auto mode on", ""].joined(separator: "\n")
    }

    @Test("keeps the conversation and drops the prompt box and status bar")
    func trimsChrome() {
        #expect(TerminalScreen.conversationTail(screen, limit: 10) == [
            "● Here is the answer", "  ⎿  Read file", "✽ Nesting… (45s · ↓ 3.9k tokens)"])
    }

    @Test("keeps only the newest lines")
    func limit() {
        #expect(TerminalScreen.conversationTail(screen, limit: 2) == ["  ⎿  Read file", "✽ Nesting… (45s · ↓ 3.9k tokens)"])
    }

    @Test("a screen without a prompt box is used whole")
    func noPromptBox() {
        #expect(TerminalScreen.conversationTail("one\n\ntwo  \n", limit: 5) == ["one", "two"])
        #expect(TerminalScreen.conversationTail("", limit: 5).isEmpty)
    }

    @Test("a rule inside the answer is not mistaken for the prompt box")
    func innerRule() {
        let text = ["intro", rule, "table", rule, "tail", rule, "❯ ", rule, "status"].joined(separator: "\n")
        #expect(TerminalScreen.conversationTail(text, limit: 10) == ["intro", rule, "table", rule, "tail"])
    }

    @Test("reads several captures printed by the script")
    func captures() {
        let us = TerminalScreen.unitSeparator
        let rs = TerminalScreen.recordSeparator
        let output = "/dev/ttys001\(rs)line a\nline b\(us)/dev/ttys002\(rs)other\(us)"
        let parsed = TerminalScreen.parseCaptures(output)
        #expect(parsed["/dev/ttys001"] == "line a\nline b")
        #expect(parsed["/dev/ttys002"] == "other")
        #expect(TerminalScreen.parseCaptures("").isEmpty)
    }
}

@Suite("Claude session board")
struct ClaudeSessionBoardTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("shows working sessions and hides idle ones")
    func workingOnly() {
        let board = ClaudeSessionBoard.empty.updated(
            with: [session("a", working: true), session("b", working: false)], now: start)
        #expect(board.visible(pinned: [], now: start).map(\.session.id) == ["a"])
    }

    @Test("a session that just stopped lingers, then fades out")
    func lingers() {
        let working = ClaudeSessionBoard.empty.updated(with: [session("a", working: true)], now: start)
        let stopped = working.updated(with: [session("a", working: false)], now: start.addingTimeInterval(2))
        #expect(stopped.visible(pinned: [], now: start.addingTimeInterval(3)).map(\.session.id) == ["a"])
        let later = start.addingTimeInterval(ClaudeSessionBoard.lingerSeconds + 1)
        #expect(stopped.visible(pinned: [], now: later).isEmpty)
    }

    @Test("a reply that finished between two scans still shows, counted from when it stopped")
    func fastReply() {
        let now = Date(timeIntervalSince1970: 5_000)
        let justStopped = ClaudeSession(id: "a", pid: 1, name: "a", cwd: "/a", isWorking: false,
                                        statusUpdatedAt: now.addingTimeInterval(-2))
        let board = ClaudeSessionBoard.empty.updated(with: [justStopped], now: now)
        #expect(board.visible(pinned: [], now: now).count == 1)
        let later = now.addingTimeInterval(ClaudeSessionBoard.lingerSeconds)
        #expect(board.visible(pinned: [], now: later).isEmpty)
    }

    @Test("a session that went idle long ago stays hidden")
    func longIdle() {
        let now = Date(timeIntervalSince1970: 5_000)
        let old = ClaudeSession(id: "a", pid: 1, name: "a", cwd: "/a", isWorking: false,
                                statusUpdatedAt: now.addingTimeInterval(-600))
        #expect(ClaudeSessionBoard.empty.updated(with: [old], now: now).visible(pinned: [], now: now).isEmpty)
    }

    @Test("a pinned session stays after it stops")
    func pinned() {
        let working = ClaudeSessionBoard.empty.updated(with: [session("a", working: true)], now: start)
        let stopped = working.updated(with: [session("a", working: false)], now: start.addingTimeInterval(10))
        let rows = stopped.visible(pinned: ["a"], now: start.addingTimeInterval(1_000))
        #expect(rows.map(\.session.id) == ["a"])
        #expect(rows.first?.isPinned == true)
    }

    @Test("a pinned session that closed is gone")
    func closed() {
        let board = ClaudeSessionBoard.empty.updated(with: [session("a", working: true)], now: start)
            .updated(with: [], now: start.addingTimeInterval(5))
        #expect(board.visible(pinned: ["a"], now: start.addingTimeInterval(5)).isEmpty)
    }

    @Test("rows keep a stable order by name")
    func order() {
        let board = ClaudeSessionBoard.empty.updated(
            with: [session("2", working: true, name: "zeta"), session("1", working: true, name: "alpha")], now: start)
        #expect(board.visible(pinned: [], now: start).map(\.session.name) == ["alpha", "zeta"])
    }

    @Test("a session already working when the app starts shows right away")
    func firstSight() {
        let board = ClaudeSessionBoard.empty.updated(with: [session("a", working: true)], now: start)
        #expect(board.visible(pinned: [], now: start).count == 1)
    }
}

@Suite("Claude quota")
struct ClaudeQuotaTests {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private func json(used: Double, resetsIn: TimeInterval) -> Data {
        let stamp = now.addingTimeInterval(resetsIn).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return Data(#"{"five_hour":{"utilization":\#(used),"resets_at":"\#(stamp)"}}"#.utf8)
    }

    @Test("reads utilization and the reset time")
    func parses() throws {
        let quota = try #require(ClaudeQuota.parse(json(used: 59, resetsIn: 3_600), fileAge: 10, now: now))
        #expect(quota.usedPercent == 59)
        #expect(quota.remainingPercent == 41)
        #expect(abs(quota.resetsAt.timeIntervalSince(now) - 3_600) < 1)
    }

    @Test("reads the microsecond timestamps the API sends")
    func microseconds() throws {
        let raw = Data(#"{"five_hour":{"utilization":59,"resets_at":"2026-11-11T10:59:59.757000+00:00"}}"#.utf8)
        let quota = try #require(ClaudeQuota.parse(raw, fileAge: 0, now: Date(timeIntervalSince1970: 1_794_000_000)))
        #expect(quota.usedPercent == 59)
    }

    @Test("an old file is not trusted")
    func stale() {
        #expect(ClaudeQuota.parse(json(used: 99, resetsIn: 3_600), fileAge: ClaudeQuota.maxAge + 1, now: now) == nil)
    }

    @Test("a window that already reset is not trusted")
    func rolledOver() {
        #expect(ClaudeQuota.parse(json(used: 99, resetsIn: -60), fileAge: 0, now: now) == nil)
    }

    @Test("garbage and missing fields give nothing")
    func garbage() {
        #expect(ClaudeQuota.parse(Data("nope".utf8), fileAge: 0, now: now) == nil)
        #expect(ClaudeQuota.parse(Data(#"{"seven_day":{}}"#.utf8), fileAge: 0, now: now) == nil)
    }

    @Test("usage over 100 leaves nothing remaining, never negative")
    func clamped() throws {
        let quota = try #require(ClaudeQuota.parse(json(used: 130, resetsIn: 60), fileAge: 0, now: now))
        #expect(quota.remainingPercent == 0)
    }
}

@Suite("Limit guard settings")
struct LimitGuardSettingsTests {
    @Test("threshold is clamped and the file tolerates missing fields")
    func clampAndDecode() throws {
        #expect(LimitGuardSettings(isEnabled: true, thresholdPercent: 0).thresholdPercent == LimitGuardSettings.minimumPercent)
        #expect(LimitGuardSettings(isEnabled: true, thresholdPercent: 99).thresholdPercent == LimitGuardSettings.maximumPercent)
        let decoded = try JSONDecoder().decode(LimitGuardSettings.self, from: Data("{}".utf8))
        #expect(decoded == .default)
        let round = try JSONDecoder().decode(LimitGuardSettings.self,
                                             from: JSONEncoder().encode(LimitGuardSettings(isEnabled: false, thresholdPercent: 8)))
        #expect(round.thresholdPercent == 8)
        #expect(!round.isEnabled)
    }
}

@Suite("Limit guard")
struct LimitGuardTests {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private let settings = LimitGuardSettings(isEnabled: true, thresholdPercent: 5)
    private func quota(remaining: Double, resetsIn: TimeInterval = 3_600) -> ClaudeQuota {
        ClaudeQuota(usedPercent: 100 - remaining, resetsAt: now.addingTimeInterval(resetsIn))
    }
    private func advance(_ guardState: LimitGuard, quota: ClaudeQuota?, sessions: [ClaudeSession],
                         settings: LimitGuardSettings? = nil, written: Bool = false, at time: Date? = nil)
        -> (LimitGuard, [LimitGuardAction]) {
        guardState.advancing(quota: quota, sessions: sessions, settings: settings ?? self.settings,
                             handoffWritten: { _, _ in written }, now: time ?? now)
    }

    @Test("does nothing while enough quota is left")
    func plenty() {
        let (_, actions) = advance(.idle, quota: quota(remaining: 6), sessions: [session("a", working: true)])
        #expect(actions.isEmpty)
    }

    @Test("asks every working session for a handoff at the threshold, and leaves idle ones alone")
    func startsHandoff() {
        let (_, actions) = advance(.idle, quota: quota(remaining: 5),
                                   sessions: [session("a", working: true), session("b", working: false),
                                              session("c", working: true)])
        #expect(actions == [.handoff(session("a", working: true)), .handoff(session("c", working: true))])
    }

    @Test("does not ask twice")
    func once() {
        let sessions = [session("a", working: true)]
        let (afterFirst, _) = advance(.idle, quota: quota(remaining: 4), sessions: sessions)
        let (_, actions) = advance(afterFirst, quota: quota(remaining: 3), sessions: sessions,
                                   at: now.addingTimeInterval(30))
        #expect(actions.isEmpty)
    }

    @Test("compacts once the handoff is written and the session has stopped")
    func compacts() {
        let (sent, _) = advance(.idle, quota: quota(remaining: 4), sessions: [session("a", working: true)])
        let (_, stillWorking) = advance(sent, quota: quota(remaining: 3), sessions: [session("a", working: true)],
                                        written: true, at: now.addingTimeInterval(30))
        #expect(stillWorking.isEmpty)
        let (done, actions) = advance(sent, quota: quota(remaining: 3), sessions: [session("a", working: false)],
                                      written: true, at: now.addingTimeInterval(40))
        #expect(actions == [.compact(session("a", working: false))])
        let (_, again) = advance(done, quota: quota(remaining: 2), sessions: [session("a", working: false)],
                                 written: true, at: now.addingTimeInterval(50))
        #expect(again.isEmpty)
    }

    @Test("waits for the handoff file, but not forever")
    func timeout() {
        let sessions = [session("a", working: false)]
        let (sent, _) = advance(.idle, quota: quota(remaining: 4), sessions: [session("a", working: true)])
        let (_, early) = advance(sent, quota: quota(remaining: 4), sessions: sessions, written: false,
                                 at: now.addingTimeInterval(60))
        #expect(early.isEmpty)
        let (_, late) = advance(sent, quota: quota(remaining: 4), sessions: sessions, written: false,
                                at: now.addingTimeInterval(LimitGuard.handoffTimeout + 1))
        #expect(late == [.compact(session("a", working: false))])
    }

    @Test("a new window starts over")
    func newWindow() {
        let sessions = [session("a", working: true)]
        let (first, _) = advance(.idle, quota: quota(remaining: 4, resetsIn: 100), sessions: sessions)
        let (_, actions) = advance(first, quota: quota(remaining: 4, resetsIn: 100 + 5 * 3_600), sessions: sessions,
                                   at: now.addingTimeInterval(1))
        #expect(actions == [.handoff(session("a", working: true))])
    }

    @Test("unknown quota or a switched-off guard never acts")
    func inert() {
        #expect(advance(.idle, quota: nil, sessions: [session("a", working: true)]).1.isEmpty)
        let off = LimitGuardSettings(isEnabled: false, thresholdPercent: 5)
        #expect(advance(.idle, quota: quota(remaining: 1), sessions: [session("a", working: true)], settings: off).1.isEmpty)
    }

    @Test("a skipped session is not retried")
    func skipped() {
        let sessions = [session("a", working: true)]
        let (sent, _) = advance(.idle, quota: quota(remaining: 4), sessions: sessions)
        let skipped = sent.skipping("a")
        let (_, actions) = advance(skipped, quota: quota(remaining: 4), sessions: [session("a", working: false)],
                                   written: true, at: now.addingTimeInterval(LimitGuard.handoffTimeout + 5))
        #expect(actions.isEmpty)
    }

    @Test("the handoff prompt names the file and the compact command points at it")
    func prompts() {
        let path = "/Users/me/.claude/handoffs/abc.md"
        #expect(LimitGuard.handoffPrompt(path: path).contains(path))
        #expect(LimitGuard.compactCommand(handoffPath: path).hasPrefix("/compact"))
        #expect(LimitGuard.compactCommand(handoffPath: path).contains(path))
        #expect(!LimitGuard.handoffPrompt(path: path).contains("\n"))
    }
}
