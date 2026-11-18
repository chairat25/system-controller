import Foundation

/// A mascot in the air after being thrown: it falls, bounces off the floor, ceiling and walls with no neighbour,
/// and flies off an edge that has one. Pure value type, so the throw is unit tested without a screen.
public struct MascotFling: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case flying(MascotFling)
        /// Came to rest on the floor at this x.
        case landed(x: Double, facesRight: Bool)
        /// Flew fully off this edge; the flight carries on on the neighbour.
        case gone(PeerSide, RoamingFlight)
    }

    static let gravity: Double = 2600
    static let wallBounce: Double = 0.5
    static let floorBounce: Double = 0.35
    static let floorFriction: Double = 0.7
    /// Below this speed a floor hit ends the flight instead of bouncing.
    static let settleSpeed: Double = 180

    /// Left edge of the mascot in points from the left of the screen; outside `0...maxX` while leaving.
    public let x: Double
    /// Height of its bottom above the floor, in points.
    public let lift: Double
    public let vx: Double
    public let vy: Double
    public let elapsed: TimeInterval

    public init(x: Double, lift: Double, vx: Double, vy: Double, elapsed: TimeInterval = 0) {
        self.x = x
        self.lift = max(lift, 0)
        self.vx = vx.isFinite ? vx : 0
        self.vy = vy.isFinite ? vy : 0
        self.elapsed = elapsed
    }

    /// A flight that came in from the next screen, starting just outside the edge it enters through.
    public static func arriving(_ flight: RoamingFlight, entry: PeerSide, maxX: Double, maxLift: Double,
                                size: Double) -> Self {
        Self(x: entry == .left ? -size : max(maxX, 0) + size, lift: flight.liftFraction * max(maxLift, 0),
             vx: flight.vx, vy: flight.vy)
    }

    public var pose: MascotPose {
        MascotPose(x: x, facesRight: vx >= 0, isWalking: false, isPickedUp: true, steps: 0, elapsed: elapsed)
    }

    /// - Parameters:
    ///   - maxX: the right-most position inside the screen.
    ///   - maxLift: the highest the mascot's bottom can be (usable height minus its size).
    public func advanced(by dt: TimeInterval, maxX: Double, maxLift: Double, size: Double,
                         canExit: (PeerSide) -> Bool) -> Outcome {
        var nextVX = vx
        var nextVY = vy - Self.gravity * dt
        var nextX = x + vx * dt
        var nextLift = lift + nextVY * dt
        let isInside = x >= 0 && x <= maxX

        if nextX < 0 || nextX > maxX {
            let side: PeerSide = nextX < 0 ? .left : .right
            if canExit(side) {
                let isGone = side == .left ? nextX <= -size : nextX >= maxX + size
                if isGone {
                    let fraction = maxLift > 0 ? nextLift / maxLift : 0
                    return .gone(side, RoamingFlight(liftFraction: fraction, vx: nextVX, vy: nextVY))
                }
            } else if isInside || (side == .left ? nextVX < 0 : nextVX > 0) {
                nextX = min(max(nextX, 0), maxX)
                nextVX = -nextVX * Self.wallBounce
            }
        }
        if nextLift > maxLift, maxLift > 0 {
            nextLift = maxLift
            nextVY = -abs(nextVY) * Self.wallBounce
        }
        if nextLift <= 0 {
            nextLift = 0
            let isInScreen = nextX >= 0 && nextX <= maxX
            if abs(nextVY) < Self.settleSpeed, isInScreen {
                return .landed(x: nextX, facesRight: nextVX >= 0)
            }
            nextVY = abs(nextVY) * Self.floorBounce
            // Sliding in from beside the screen keeps its speed, so it never stops outside.
            if isInScreen { nextVX *= Self.floorFriction }
        }
        return .flying(Self(x: nextX, lift: nextLift, vx: nextVX, vy: nextVY, elapsed: elapsed + dt))
    }
}
