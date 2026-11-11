import Foundation
import Testing
@testable import SoundControlCore

@Suite("Idle compact settings")
struct IdleCompactTests {
    @Test("defaults are enabled at 15 minutes")
    func defaults() {
        let settings = IdleCompactSettings.default
        #expect(settings.isEnabled)
        #expect(settings.idleMinutes == 15)
        #expect(settings.idleSeconds == 900)
    }

    @Test("minutes are clamped to the allowed range")
    func clamping() {
        #expect(IdleCompactSettings(isEnabled: true, idleMinutes: 0).idleMinutes == IdleCompactSettings.minimumMinutes)
        #expect(IdleCompactSettings(isEnabled: true, idleMinutes: 500).idleMinutes == IdleCompactSettings.maximumMinutes)
        #expect(IdleCompactSettings(isEnabled: true, idleMinutes: 30).idleMinutes == 30)
    }

    @Test("withIdleMinutes clamps and keeps enabled state")
    func updates() {
        let settings = IdleCompactSettings.default.withIdleMinutes(999).withEnabled(false)
        #expect(settings.idleMinutes == IdleCompactSettings.maximumMinutes)
        #expect(!settings.isEnabled)
    }

    @Test("round-trips through JSON with the keys the hook script reads")
    func codable() throws {
        let settings = IdleCompactSettings(isEnabled: false, idleMinutes: 45)
        let data = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["enabled"] as? Bool == false)
        #expect(object["idleMinutes"] as? Int == 45)
        #expect(try JSONDecoder().decode(IdleCompactSettings.self, from: data) == settings)
    }

    @Test("missing or out-of-range fields fall back to defaults")
    func lenientDecoding() throws {
        let partial = try JSONDecoder().decode(IdleCompactSettings.self, from: Data("{}".utf8))
        #expect(partial == .default)
        let outOfRange = try JSONDecoder().decode(IdleCompactSettings.self,
                                                  from: Data(#"{"enabled":true,"idleMinutes":-3}"#.utf8))
        #expect(outOfRange.idleMinutes == IdleCompactSettings.minimumMinutes)
    }
}

@Suite("Idle compactor")
struct IdleCompactorTests {
    private let start = Date(timeIntervalSince1970: 10_000)
    private let settings = IdleCompactSettings(isEnabled: true, idleMinutes: 15)

    private func session(working: Bool, changedAt: TimeInterval) -> ClaudeSession {
        ClaudeSession(id: "a", pid: 1, name: "a", cwd: "/a", isWorking: working,
                      statusUpdatedAt: start.addingTimeInterval(changedAt))
    }

    private func step(_ state: IdleCompactor, _ session: ClaudeSession, at offset: TimeInterval,
                      settings: IdleCompactSettings? = nil) -> (IdleCompactor, [ClaudeSession]) {
        state.advancing(sessions: [session], settings: settings ?? self.settings, now: start.addingTimeInterval(offset))
    }

    @Test("a session already idle when the app starts is left alone")
    func staleAtLaunch() {
        let (first, a) = step(.initial, session(working: false, changedAt: -86_400), at: 0)
        let (_, b) = step(first, session(working: false, changedAt: -86_400), at: 3_600)
        #expect(a.isEmpty && b.isEmpty)
    }

    @Test("compacts once after a turn ends and the session stays idle long enough")
    func compactsOnce() {
        let (seen, _) = step(.initial, session(working: true, changedAt: 0), at: 0)
        let (stopped, early) = step(seen, session(working: false, changedAt: 60), at: 60 + 899)
        #expect(early.isEmpty)
        let (done, due) = step(stopped, session(working: false, changedAt: 60), at: 60 + 900)
        #expect(due.count == 1)
        let (_, again) = step(done, session(working: false, changedAt: 60), at: 60 + 5_000)
        #expect(again.isEmpty)
    }

    @Test("the status changes caused by /compact do not trigger another one")
    func ignoresOwnCompaction() {
        let (seen, _) = step(.initial, session(working: true, changedAt: 0), at: 0)
        let (stopped, _) = step(seen, session(working: false, changedAt: 10), at: 11)
        let (compacted, due) = step(stopped, session(working: false, changedAt: 10), at: 910)
        #expect(due.count == 1)
        let (busy, _) = step(compacted, session(working: true, changedAt: 920), at: 921)
        let (settled, _) = step(busy, session(working: false, changedAt: 960), at: 961)
        let (_, later) = step(settled, session(working: false, changedAt: 960), at: 960 + 2_000)
        #expect(later.isEmpty)
    }

    @Test("new work after the compaction arms it again")
    func rearms() {
        let (seen, _) = step(.initial, session(working: true, changedAt: 0), at: 0)
        let (stopped, _) = step(seen, session(working: false, changedAt: 10), at: 11)
        let (compacted, _) = step(stopped, session(working: false, changedAt: 10), at: 910)
        let newTurnEnd = 910 + IdleCompactor.settleSeconds + 100
        let (again, _) = step(compacted, session(working: false, changedAt: newTurnEnd), at: newTurnEnd + 1)
        let (_, due) = step(again, session(working: false, changedAt: newTurnEnd), at: newTurnEnd + 900)
        #expect(due.count == 1)
    }

    @Test("never acts while switched off or while the session works")
    func inert() {
        let off = IdleCompactSettings(isEnabled: false, idleMinutes: 15)
        let (seen, _) = step(.initial, session(working: true, changedAt: 0), at: 0, settings: off)
        let (stopped, _) = step(seen, session(working: false, changedAt: 10), at: 11, settings: off)
        #expect(step(stopped, session(working: false, changedAt: 10), at: 5_000, settings: off).1.isEmpty)
        let (busy, _) = step(seen, session(working: true, changedAt: 10), at: 11)
        #expect(step(busy, session(working: true, changedAt: 10), at: 5_000).1.isEmpty)
    }
}
