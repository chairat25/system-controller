import Foundation
import Testing
@testable import SoundControlCore

@Suite("Sleep gating")
struct SleepGateTests {
    let now = Date(timeIntervalSince1970: 12 * 3600)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test("plays normally while the Mac is awake")
    func awake() {
        #expect(PlaybackGate.decide(.chargerConnected, config: .default, now: now, lastPlayed: nil,
                                    asleepSince: nil, calendar: calendar) == .play)
    }

    @Test("the sleep sound itself still plays right after the Mac starts going to sleep")
    func graceAfterSleep() {
        let justNow = now.addingTimeInterval(-1)
        #expect(PlaybackGate.decide(.macSleeps, config: .default, now: now, lastPlayed: nil,
                                    asleepSince: justNow, calendar: calendar) == .play)
    }

    @Test("events during sleep or a dark wake are skipped")
    func skipsWhileAsleep() {
        let earlier = now.addingTimeInterval(-(PlaybackGate.sleepGrace + 60))
        #expect(PlaybackGate.decide(.chargerConnected, config: .default, now: now, lastPlayed: nil,
                                    asleepSince: earlier, calendar: calendar) == .skipped(.asleep))
        #expect(SkipReason.asleep.isWorthLogging)
    }
}
