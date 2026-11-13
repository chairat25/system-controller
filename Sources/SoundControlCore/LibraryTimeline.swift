import Foundation

/// Which day bucket an activity event belongs to on the Activity timeline.
public enum ActivityDay: String, CaseIterable, Sendable {
    case today = "Today", yesterday = "Yesterday", earlier = "Earlier"
}

/// What the Activity page shows. Only states the log actually records: played or skipped.
public enum ActivityFilter: String, CaseIterable, Sendable {
    case all = "All", played = "Played", skipped = "Skipped"

    public func matches(_ entry: ActivityEntry) -> Bool {
        switch self {
        case .all: true
        case .played: entry.didPlay
        case .skipped: !entry.didPlay
        }
    }
}

public enum ActivityTimeline {
    public struct Group: Sendable, Equatable {
        public let day: ActivityDay
        public let entries: [ActivityEntry]
    }

    /// Splits events into Today, Yesterday and Earlier, newest first. Days with no events are left out.
    public static func groups(_ entries: [ActivityEntry], now: Date, calendar: Calendar) -> [Group] {
        let sorted = entries.sorted { $0.date > $1.date }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func day(of entry: ActivityEntry) -> ActivityDay {
            if entry.date >= today { return .today }
            if entry.date >= yesterday { return .yesterday }
            return .earlier
        }
        return ActivityDay.allCases.compactMap { bucket in
            let matching = sorted.filter { day(of: $0) == bucket }
            return matching.isEmpty ? nil : Group(day: bucket, entries: matching)
        }
    }
}

/// Filtering and sorting for the My Sounds library.
public enum UserSoundLibrary {
    public enum Filter: String, CaseIterable, Sendable {
        case all = "All", used = "Used", unused = "Unused"
    }

    public enum Sort: String, CaseIterable, Sendable {
        case name = "Name", recent = "Recently added", duration = "Duration"
    }

    public static func sorted(_ sounds: [UserSound], by sort: Sort) -> [UserSound] {
        switch sort {
        case .name: sounds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: sounds.sorted { $0.addedAt > $1.addedAt }
        case .duration: sounds.sorted { $0.duration > $1.duration }
        }
    }

    public static func filtered(_ sounds: [UserSound], by filter: Filter, search: String,
                                usage: (UUID) -> Int) -> [UserSound] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return sounds.filter { sound in
            let matchesSearch = query.isEmpty || sound.name.localizedCaseInsensitiveContains(query)
            let count = usage(sound.id)
            let matchesFilter = filter == .all || (filter == .used && count > 0) || (filter == .unused && count == 0)
            return matchesSearch && matchesFilter
        }
    }

    /// How many triggers and custom pack slots point at this sound.
    public static func usageCount(of id: UUID, in config: AppConfig) -> Int {
        let ref = SoundRef.user(id: id)
        let direct = config.triggers.values.filter { $0.customSounds.contains(ref) }.count
        let inPacks = config.customPacks.flatMap { $0.overrides.values }.filter { $0.contains(ref) }.count
        return direct + inPacks
    }

    public static func format(of sound: UserSound) -> String {
        (sound.fileName as NSString).pathExtension.uppercased()
    }
}
