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
    /// Distance from the top of the walk area, in points.
    public let y: Double
    public let facesRight: Bool
    public let isWalking: Bool
    public let isPickedUp: Bool
    /// Steps taken so far; the fraction drives the leg swing.
    public let steps: Double
    /// Seconds since this pause or walk began, for blinking and breathing.
    public let elapsed: TimeInterval

    public init(x: Double, y: Double = 0, facesRight: Bool, isWalking: Bool,
                isPickedUp: Bool = false, steps: Double, elapsed: TimeInterval) {
        self.x = x
        self.y = y
        self.facesRight = facesRight
        self.isWalking = isWalking
        self.isPickedUp = isPickedUp
        self.steps = steps
        self.elapsed = elapsed
    }
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
    /// How far the mascot can walk horizontally, in points.
    public let width: Double
    /// How far the mascot can walk vertically, in points (0 for a 1D horizontal stroll).
    public let height: Double
    public let startX: Double?
    public let startY: Double?

    public init(seed: UInt64, width: Double, height: Double = 0, startX: Double? = nil, startY: Double? = nil) {
        let clampedWidth = max(width, 0)
        let clampedHeight = max(height, 0)
        self.seed = seed
        self.width = clampedWidth
        self.height = clampedHeight
        self.startX = startX.map { min(max($0, 0), clampedWidth) }
        self.startY = startY.map { min(max($0, 0), clampedHeight) }
    }

    /// The pose `time` seconds after the stroll began, and the cursor to pass in next time.
    public func pose(at time: TimeInterval, from cursor: Cursor = .origin) -> (MascotPose, Cursor) {
        var current = time < cursor.start ? Cursor.origin : cursor
        while time >= current.start + duration(of: current.leg) {
            current = Cursor(leg: current.leg + 1, start: current.start + duration(of: current.leg))
        }
        let local = max(time - current.start, 0)
        let fromX = stop(current.leg)
        let toX = stop(current.leg + 1)
        let fromY = stopY(current.leg)
        let toY = stopY(current.leg + 1)
        let dx = toX - fromX
        let dy = toY - fromY
        let distance = hypot(dx, dy)
        let facesRight = dx >= 0
        let pause = pause(current.leg)
        guard local >= pause, distance > 0 else {
            return (MascotPose(x: fromX, y: fromY, facesRight: facesRight, isWalking: false, steps: 0, elapsed: local), current)
        }
        let walked = min((local - pause) * Self.speed, distance)
        let progress = walked / distance
        let pose = MascotPose(x: fromX + dx * progress, y: fromY + dy * progress,
                              facesRight: facesRight, isWalking: true,
                              steps: walked / Self.stepLength, elapsed: local - pause)
        return (pose, current)
    }

    /// The horizontal spot where leg `leg` starts.
    func stop(_ leg: Int) -> Double {
        leg == 0 ? (startX ?? width / 2) : unit(leg, salt: 1) * width
    }

    /// The vertical spot where leg `leg` starts.
    func stopY(_ leg: Int) -> Double {
        leg == 0 ? (startY ?? height / 2) : unit(leg, salt: 3) * height
    }

    func pause(_ leg: Int) -> TimeInterval {
        Self.minimumPause + unit(leg, salt: 2) * Self.pauseRange
    }

    func duration(of leg: Int) -> TimeInterval {
        let dx = stop(leg + 1) - stop(leg)
        let dy = stopY(leg + 1) - stopY(leg)
        return pause(leg) + hypot(dx, dy) / Self.speed
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
