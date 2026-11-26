import Foundation

/// A window a mascot can climb, in the mascot's own coordinates: x from the left of the usable screen area,
/// heights (`bottom`, `top`) above its floor.
public struct ClimbSurface: Sendable, Equatable {
    public let id: Int
    public let minX: Double
    public let maxX: Double
    public let bottom: Double
    public let top: Double

    public init(id: Int, minX: Double, maxX: Double, bottom: Double, top: Double) {
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.bottom = bottom
        self.top = top
    }
}

/// A mascot on a window: it climbs up one side, strolls along the top edge, and after a while jumps off an end
/// back down to the floor. If the window moves it is carried along; if it closes, the mascot falls. Pure value
/// type, so the climb is unit tested without a screen.
public struct WindowClimber: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case climbing(WindowClimber)
        /// Left the window; the fall continues as a throw from here.
        case jumped(MascotFling)
    }

    static let climbSpeed: Double = 70
    static let jumpSpeed: Double = 140
    static let jumpLift: Double = 260
    /// How far above the floor a window may start and still be climbed from it, as a share of the mascot's size.
    static let reachableBottom: Double = 0.6
    /// Shorter windows are not worth climbing.
    static let minimumHeight: Double = 2
    static let minimumStay: TimeInterval = 5
    static let stayRange: TimeInterval = 12

    public let surfaceID: Int
    /// Left edge of the mascot, like `RoamingWalker.x`.
    public let x: Double
    /// Height of its bottom above the floor.
    public let lift: Double
    public let facesRight: Bool
    public let isOnTop: Bool
    public let steps: Double
    public let elapsed: TimeInterval
    /// Seconds left to stroll on top before it takes the next end to jump off.
    private let stayLeft: TimeInterval
    /// Where its middle sits on the surface, as an offset from the surface's left edge, so a moving window carries it.
    private let offset: Double

    public var pose: MascotPose {
        MascotPose(x: x, y: 0, facesRight: facesRight, isWalking: true, steps: steps, elapsed: elapsed)
    }

    /// The window whose side is just ahead of a walker on the floor and that it can climb: standing on (or near)
    /// the floor and tall enough. The side may be the near side of a window beyond it, or the far side of a window
    /// it walks in front of (a window as wide as the screen has no other side it can reach).
    public static func surface(ahead walker: RoamingWalker, in surfaces: [ClimbSurface], size: Double) -> ClimbSurface? {
        guard walker.isWalking, walker.phase == .inside else { return nil }
        let front = walker.facesRight ? walker.x + size : walker.x
        return surfaces.first { surface in
            surface.bottom <= size * reachableBottom && surface.top - surface.bottom >= size * minimumHeight
                && nearestSide(of: surface, to: front, size: size) != nil
        }
    }

    /// Starts climbing the side of the window nearest `front` (the leading edge of the walker); without it, the
    /// side it faces: the left side when walking right, the right side when walking left.
    public static func start(on surface: ClimbSurface, facingRight: Bool, size: Double, seed: UInt64,
                             front: Double? = nil) -> Self {
        let middle = front.flatMap { nearestSide(of: surface, to: $0, size: .infinity) }
            ?? (facingRight ? surface.minX : surface.maxX)
        let roll = Double(seed % 1000) / 1000
        return Self(surfaceID: surface.id, x: middle - size / 2, lift: 0, facesRight: facingRight, isOnTop: false,
                    steps: 0, elapsed: 0, stayLeft: minimumStay + roll * stayRange, offset: middle - surface.minX)
    }

    private static func nearestSide(of surface: ClimbSurface, to front: Double, size: Double) -> Double? {
        let reach = size * 0.25
        let side = abs(front - surface.minX) <= abs(front - surface.maxX) ? surface.minX : surface.maxX
        return abs(front - side) <= reach ? side : nil
    }

    public func advanced(by dt: TimeInterval, surfaces: [ClimbSurface], size: Double) -> Outcome {
        guard let surface = surfaces.first(where: { $0.id == surfaceID }) else {
            return .jumped(MascotFling(x: x, lift: lift, vx: 0, vy: 0))
        }
        let step = Self.climbSpeed * dt
        let nextSteps = steps + step / MascotRoute.stepLength
        let moved = { (climber: Self) in climber.aged(by: dt) }
        guard isOnTop else {
            let nextLift = min(lift + step, surface.top)
            let middle = surface.minX + offset
            return .climbing(moved(copy(x: middle - size / 2, lift: nextLift, isOnTop: nextLift >= surface.top,
                                  steps: nextSteps, offset: offset)))
        }
        let direction: Double = facesRight ? 1 : -1
        let nextOffset = offset + direction * step
        let width = surface.maxX - surface.minX
        if nextOffset < 0 || nextOffset > width {
            if stayLeft <= 0 {
                let edge = nextOffset < 0 ? surface.minX - size / 2 - 1 : surface.maxX - size / 2 + 1
                return .jumped(MascotFling(x: edge, lift: surface.top, vx: direction * Self.jumpSpeed, vy: Self.jumpLift))
            }
            let clamped = min(max(nextOffset, 0), width)
            return .climbing(moved(copy(x: surface.minX + clamped - size / 2, lift: surface.top, facesRight: !facesRight,
                                  steps: nextSteps, offset: clamped, stayLeft: stayLeft - dt)))
        }
        return .climbing(moved(copy(x: surface.minX + nextOffset - size / 2, lift: surface.top, steps: nextSteps,
                              offset: nextOffset, stayLeft: stayLeft - dt)))
    }

    private func aged(by dt: TimeInterval) -> Self {
        Self(surfaceID: surfaceID, x: x, lift: lift, facesRight: facesRight, isOnTop: isOnTop, steps: steps,
             elapsed: elapsed + dt, stayLeft: stayLeft, offset: offset)
    }

    private func copy(x: Double, lift: Double, facesRight: Bool? = nil, isOnTop: Bool? = nil, steps: Double,
                      offset: Double, stayLeft: TimeInterval? = nil) -> Self {
        Self(surfaceID: surfaceID, x: x, lift: lift, facesRight: facesRight ?? self.facesRight,
             isOnTop: isOnTop ?? self.isOnTop, steps: steps, elapsed: elapsed, stayLeft: stayLeft ?? self.stayLeft,
             offset: offset)
    }

    private init(surfaceID: Int, x: Double, lift: Double, facesRight: Bool, isOnTop: Bool, steps: Double,
                 elapsed: TimeInterval, stayLeft: TimeInterval, offset: Double) {
        self.surfaceID = surfaceID
        self.x = x
        self.lift = lift
        self.facesRight = facesRight
        self.isOnTop = isOnTop
        self.steps = steps
        self.elapsed = elapsed
        self.stayLeft = stayLeft
        self.offset = offset
    }
}
