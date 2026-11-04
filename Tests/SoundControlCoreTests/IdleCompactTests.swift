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
