import Foundation
import Testing
@testable import SoundControlCore

@Suite("Activity timeline")
struct ActivityTimelineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC

    private func entry(hoursAgo: Double, skipped: SkipReason? = nil) -> ActivityEntry {
        ActivityEntry(trigger: TriggerID.allCases[0], date: now.addingTimeInterval(-hoursAgo * 3600),
                      skipReason: skipped, soundName: "Chime", context: nil)
    }

    @Test("events fall into Today, Yesterday and Earlier, newest first, empty days left out")
    func groups() {
        let entries = [entry(hoursAgo: 1), entry(hoursAgo: 30), entry(hoursAgo: 2), entry(hoursAgo: 80)]
        let groups = ActivityTimeline.groups(entries, now: now, calendar: calendar)
        #expect(groups.map(\.day) == [.today, .yesterday, .earlier])
        #expect(groups[0].entries.count == 2)
        #expect(groups[0].entries[0].date > groups[0].entries[1].date)
        #expect(ActivityTimeline.groups([entry(hoursAgo: 1)], now: now, calendar: calendar).map(\.day) == [.today])
    }

    @Test("filter keeps played or skipped events")
    func filter() {
        let played = entry(hoursAgo: 1)
        let skipped = entry(hoursAgo: 1, skipped: .quietHours)
        #expect(ActivityFilter.all.matches(skipped))
        #expect(ActivityFilter.played.matches(played))
        #expect(!ActivityFilter.played.matches(skipped))
        #expect(ActivityFilter.skipped.matches(skipped))
        #expect(!ActivityFilter.skipped.matches(played))
    }
}

@Suite("Sound library")
struct SoundLibraryTests {
    private let sounds: [UserSound] = [
        UserSound(name: "Bell", fileName: "bell.wav", duration: 3, addedAt: Date(timeIntervalSince1970: 1_000)),
        UserSound(name: "applause", fileName: "applause.mp3", duration: 1, addedAt: Date(timeIntervalSince1970: 2_000))
    ]

    @Test("sorts by name ignoring case, newest first, or longest first")
    func sorts() {
        #expect(UserSoundLibrary.sorted(sounds, by: .name).map(\.name) == ["applause", "Bell"])
        #expect(UserSoundLibrary.sorted(sounds, by: .recent).map(\.name) == ["applause", "Bell"])
        #expect(UserSoundLibrary.sorted(sounds, by: .duration).map(\.name) == ["Bell", "applause"])
    }

    @Test("format is the file extension in capitals")
    func format() {
        #expect(UserSoundLibrary.format(of: sounds[1]) == "MP3")
    }

    @Test("used and unused split on the usage count, search matches the name")
    func filters() {
        let used: Set<UUID> = [sounds[0].id]
        let usage: (UUID) -> Int = { used.contains($0) ? 1 : 0 }
        #expect(UserSoundLibrary.filtered(sounds, by: .used, search: "", usage: usage).map(\.name) == ["Bell"])
        #expect(UserSoundLibrary.filtered(sounds, by: .unused, search: "", usage: usage).map(\.name) == ["applause"])
        #expect(UserSoundLibrary.filtered(sounds, by: .all, search: "APP", usage: usage).map(\.name) == ["applause"])
    }
}
