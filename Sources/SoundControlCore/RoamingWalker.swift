import Foundation

/// One roaming object walking along the bottom of a screen: it strolls, pauses, turns around at an edge with no
/// neighbour, and leaves through an edge that has one. Pure value type, so the walk is unit tested without a screen.
public struct RoamingWalker: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case inside
        case entering
        case leaving(PeerSide)
    }

    static let minimumWalk: TimeInterval = 4
    static let walkRange: TimeInterval = 8
    static let minimumPause: TimeInterval = 2
    static let pauseRange: TimeInterval = 5
    /// Running away is this many times a walk.
    static let runFactor: Double = 3.2
    /// How long one scare makes it run.
    static let fleeDuration: TimeInterval = 1.8
    /// How long a held pose or a heading lasts without being asked for again.
    static let holdTime: TimeInterval = 1

    public let id: String
    public let kind: RoamingKind
    /// Left edge of the object, in points from the left end of the screen. Outside `0...maxX` while crossing an edge.
    public let x: Double
    public let yFraction: Double
    public let facesRight: Bool
    public let isWalking: Bool
    /// Running away after being clicked too much.
    public let isRunning: Bool
    public let phase: Phase
    /// Steps taken so far; the fraction drives the leg swing.
    public let steps: Double
    /// Seconds since this walk or pause began.
    public let elapsed: TimeInterval
    private let timeLeft: TimeInterval
    private let randomState: UInt64

    public var pose: MascotPose {
        MascotPose(x: x, y: 0, facesRight: facesRight, isWalking: isWalking, isRunning: isRunning, steps: steps,
                   elapsed: elapsed)
    }

    /// A new object resting somewhere on the screen.
    public static func spawn(id: String, kind: RoamingKind = .mascot, yFraction: Double, maxX: Double, seed: UInt64) -> Self {
        let (placement, afterPlacement) = roll(seed)
        let (pause, state) = roll(afterPlacement)
        return Self(id: id, kind: kind, x: placement * max(maxX, 0), yFraction: yFraction, facesRight: placement < 0.5,
                    isWalking: false, isRunning: false, phase: .inside, steps: 0, elapsed: 0,
                    timeLeft: minimumPause + pause * pauseRange, randomState: state)
    }

    /// An object that came down on the floor after a throw: it rests where it landed, then strolls on.
    public static func landed(id: String, kind: RoamingKind = .mascot, x: Double, facesRight: Bool, seed: UInt64) -> Self {
        Self(id: id, kind: kind, x: x, yFraction: 1, facesRight: facesRight, isWalking: false, isRunning: false,
             phase: .inside, steps: 0, elapsed: 0, timeLeft: minimumPause, randomState: seed)
    }

    /// An object that arrived from the next screen: it walks in from the edge it was handed over at.
    public static func arriving(_ object: RoamingObject, maxX: Double, size: Double, seed: UInt64) -> Self {
        let isFromLeft = object.entryEdge == .left
        if object.state == .resting {
            return Self(id: object.id, kind: object.kind, x: isFromLeft ? 0 : max(maxX, 0), yFraction: object.yFraction,
                        facesRight: isFromLeft, isWalking: false, isRunning: false, phase: .inside, steps: 0,
                        elapsed: 0, timeLeft: minimumPause, randomState: seed)
        }
        return Self(id: object.id, kind: object.kind, x: isFromLeft ? -size : max(maxX, 0) + size,
                    yFraction: object.yFraction, facesRight: isFromLeft, isWalking: true, isRunning: false,
                    phase: .entering, steps: 0, elapsed: 0, timeLeft: 0, randomState: seed)
    }

    /// Runs off the other way from `pointX` (the mouse, in the same points as `x`). Only while walking or
    /// resting on this screen; it keeps running for a moment, then catches its breath.
    public func fleeing(from pointX: Double, size: Double) -> Self {
        guard phase == .inside else { return self }
        let towardRight = pointX < x + size / 2
        return copy(facesRight: towardRight, isWalking: true, isRunning: true, elapsed: 0,
                    timeLeft: Self.fleeDuration)
    }

    /// Holds still where it is, turned this way (nil keeps the way it faces), while the owner of the walk keeps
    /// asking for it each frame. Only on this screen; it strolls on again soon after the asking stops.
    public func standing(facesRight: Bool?) -> Self {
        guard phase == .inside else { return self }
        return copy(facesRight: facesRight ?? self.facesRight, isWalking: false, isRunning: false,
                    elapsed: isWalking ? 0 : elapsed, timeLeft: Self.holdTime)
    }

    /// Heads for a point (the middle of the object, like `x` plus half its size), walking or running, while the
    /// owner keeps asking each frame. Only on this screen.
    public func heading(towardX target: Double, size: Double, running: Bool) -> Self {
        guard phase == .inside else { return self }
        let faces = target >= x + size / 2
        return copy(facesRight: faces, isWalking: true, isRunning: running, elapsed: isWalking ? elapsed : 0,
                    timeLeft: Self.holdTime)
    }

    /// The walker `dt` seconds later, plus the object to hand over when it has walked fully off an edge
    /// (the walker is then finished and should be dropped).
    /// - Parameters:
    ///   - maxX: the right-most position inside the screen (screen width minus object size).
    ///   - canExit: whether a neighbour is reachable beyond that edge.
    public func advanced(by dt: TimeInterval, maxX: Double, size: Double,
                         canExit: (PeerSide) -> Bool) -> (walker: Self, handoff: RoamingObject?) {
        let step = Self.speed * (isRunning ? Self.runFactor : 1) * dt
        let direction: Double = facesRight ? 1 : -1
        switch phase {
        case let .leaving(side):
            let nextX = x + direction * step
            let isGone = side == .left ? nextX <= -size : nextX >= maxX + size
            let next = copy(x: nextX, steps: steps + step / MascotRoute.stepLength, elapsed: elapsed + dt)
            return (next, isGone ? handoff(side: side) : nil)
        case .entering:
            let nextX = x + direction * step
            let isInside = nextX >= 0 && nextX <= maxX
            return (resumedWalk(copy(x: nextX, steps: steps + step / MascotRoute.stepLength, elapsed: elapsed + dt),
                                isInside: isInside), nil)
        case .inside:
            return (isWalking ? walked(dt: dt, step: step, direction: direction, maxX: maxX, canExit: canExit)
                              : rested(dt: dt), nil)
        }
    }

    private static var speed: Double { MascotRoute.speed }

    private func handoff(side: PeerSide) -> RoamingObject {
        RoamingObject(id: id, kind: kind, yFraction: yFraction, direction: side == .left ? .left : .right, state: .walking)
    }

    private func resumedWalk(_ walker: Self, isInside: Bool) -> Self {
        guard isInside else { return walker }
        let (walk, state) = Self.roll(randomState)
        return walker.copy(phase: .inside, timeLeft: Self.minimumWalk + walk * Self.walkRange, randomState: state)
    }

    private func walked(dt: TimeInterval, step: Double, direction: Double, maxX: Double,
                        canExit: (PeerSide) -> Bool) -> Self {
        let nextX = x + direction * step
        let nextSteps = steps + step / MascotRoute.stepLength
        if nextX <= 0 || nextX >= maxX {
            let side: PeerSide = nextX <= 0 ? .left : .right
            if canExit(side) {
                return copy(x: nextX, phase: .leaving(side), steps: nextSteps, elapsed: elapsed + dt)
            }
            // No neighbour that way. A runner is cornered and stops; a walker turns around.
            if isRunning {
                return rest(x: min(max(nextX, 0), maxX), steps: nextSteps)
            }
            return copy(x: min(max(nextX, 0), maxX), facesRight: !facesRight, steps: nextSteps, elapsed: elapsed + dt)
        }
        guard timeLeft - dt <= 0 else {
            return copy(x: nextX, steps: nextSteps, elapsed: elapsed + dt, timeLeft: timeLeft - dt)
        }
        return rest(x: nextX, steps: nextSteps)
    }

    private func rest(x: Double, steps: Double) -> Self {
        let (pause, state) = Self.roll(randomState)
        return copy(x: x, isWalking: false, isRunning: false, steps: steps, elapsed: 0,
                    timeLeft: Self.minimumPause + pause * Self.pauseRange, randomState: state)
    }

    private func rested(dt: TimeInterval) -> Self {
        guard timeLeft - dt <= 0 else { return copy(elapsed: elapsed + dt, timeLeft: timeLeft - dt) }
        let (direction, afterDirection) = Self.roll(randomState)
        let (walk, state) = Self.roll(afterDirection)
        return copy(facesRight: direction < 0.5, isWalking: true, elapsed: 0,
                    timeLeft: Self.minimumWalk + walk * Self.walkRange, randomState: state)
    }

    private func copy(x: Double? = nil, facesRight: Bool? = nil, isWalking: Bool? = nil, isRunning: Bool? = nil,
                      phase: Phase? = nil, steps: Double? = nil, elapsed: TimeInterval? = nil, timeLeft: TimeInterval? = nil,
                      randomState: UInt64? = nil) -> Self {
        Self(id: id, kind: kind, x: x ?? self.x, yFraction: yFraction, facesRight: facesRight ?? self.facesRight,
             isWalking: isWalking ?? self.isWalking, isRunning: isRunning ?? self.isRunning,
             phase: phase ?? self.phase, steps: steps ?? self.steps,
             elapsed: elapsed ?? self.elapsed, timeLeft: timeLeft ?? self.timeLeft,
             randomState: randomState ?? self.randomState)
    }

    private init(id: String, kind: RoamingKind, x: Double, yFraction: Double, facesRight: Bool, isWalking: Bool,
                 isRunning: Bool, phase: Phase, steps: Double, elapsed: TimeInterval, timeLeft: TimeInterval,
                 randomState: UInt64) {
        self.id = id
        self.kind = kind
        self.x = x
        self.yFraction = yFraction
        self.facesRight = facesRight
        self.isWalking = isWalking
        self.isRunning = isRunning
        self.phase = phase
        self.steps = steps
        self.elapsed = elapsed
        self.timeLeft = timeLeft
        self.randomState = randomState
    }

    /// A number in 0..<1 and the next generator state (SplitMix64).
    private static func roll(_ state: UInt64) -> (Double, UInt64) {
        let next = state &+ 0x9E37_79B9_7F4A_7C15
        var value = next
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return (Double(value >> 11) / Double(1 << 53), next)
    }
}
