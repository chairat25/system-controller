import Foundation

/// The little animal that wanders along the bottom of the screen saver, so a locked screen looks friendly.
public enum Mascot: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, cat, puppy, bunny, panda, penguin

    public static let animals: [Mascot] = allCases.filter { $0 != .none }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .cat: "Cat"
        case .puppy: "Puppy"
        case .bunny: "Bunny"
        case .panda: "Panda"
        case .penguin: "Penguin"
        }
    }
}

/// Where the mascot is and what it is doing at one moment.
public struct MascotPose: Sendable, Equatable {
    /// Distance from the left end of the walk, in points.
    public let x: Double
    public let facesRight: Bool
    public let isWalking: Bool
    /// Steps taken so far; the fraction drives the leg swing.
    public let steps: Double
    /// Seconds since this pause or walk began, for blinking and breathing.
    public let elapsed: TimeInterval
}

/// A never-ending stroll: pause at a spot, walk to the next one, pause again.
/// Every stop and pause comes from the seed, so the route needs no stored history and costs nothing to keep.
public struct MascotRoute: Sendable {
    public static let speed: Double = 60
    public static let stepLength: Double = 14
    static let minimumPause: TimeInterval = 2
    static let pauseRange: TimeInterval = 5

    /// Remembers the leg the last pose fell in, so the next pose starts there instead of at the very first leg.
    public struct Cursor: Sendable, Equatable {
        public static let origin = Cursor(leg: 0, start: 0)
        let leg: Int
        let start: TimeInterval
    }

    public let seed: UInt64
    /// How far the mascot can walk, in points.
    public let width: Double

    public init(seed: UInt64, width: Double) {
        self.seed = seed
        self.width = max(width, 0)
    }

    /// The pose `time` seconds after the stroll began, and the cursor to pass in next time.
    public func pose(at time: TimeInterval, from cursor: Cursor = .origin) -> (MascotPose, Cursor) {
        var current = time < cursor.start ? Cursor.origin : cursor
        while time >= current.start + duration(of: current.leg) {
            current = Cursor(leg: current.leg + 1, start: current.start + duration(of: current.leg))
        }
        let local = max(time - current.start, 0)
        let from = stop(current.leg)
        let to = stop(current.leg + 1)
        let facesRight = to >= from
        let pause = pause(current.leg)
        guard local >= pause, to != from else {
            return (MascotPose(x: from, facesRight: facesRight, isWalking: false, steps: 0, elapsed: local), current)
        }
        let walked = min((local - pause) * Self.speed, abs(to - from))
        let pose = MascotPose(x: from + (facesRight ? walked : -walked), facesRight: facesRight, isWalking: true,
                              steps: walked / Self.stepLength, elapsed: local - pause)
        return (pose, current)
    }

    /// The spot where leg `leg` starts.
    func stop(_ leg: Int) -> Double {
        leg == 0 ? width / 2 : unit(leg, salt: 1) * width
    }

    func pause(_ leg: Int) -> TimeInterval {
        Self.minimumPause + unit(leg, salt: 2) * Self.pauseRange
    }

    func duration(of leg: Int) -> TimeInterval {
        pause(leg) + abs(stop(leg + 1) - stop(leg)) / Self.speed
    }

    /// A repeatable number in 0..<1 for this leg (SplitMix64).
    private func unit(_ leg: Int, salt: UInt64) -> Double {
        var value = seed &+ UInt64(truncatingIfNeeded: leg) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
