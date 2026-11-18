import Foundation

/// What kind of thing walks between screens. The mascot is the first; others can follow.
public enum RoamingKind: String, Codable, Sendable, CaseIterable {
    case mascot
}

public enum RoamingDirection: String, Codable, Sendable {
    case left, right

    /// The screen edge an object walking this way leaves through.
    public var exitEdge: PeerSide { self == .left ? .left : .right }
}

public enum RoamingState: String, Codable, Sendable {
    case walking, resting
}

/// Something handed from one screen to the one beside it.
public struct RoamingObject: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: RoamingKind
    /// Height on the screen, 0 at the top and 1 at the bottom of the usable area.
    public let yFraction: Double
    /// The way it was walking when it left.
    public let direction: RoamingDirection
    public let state: RoamingState
    /// The Mac it was born on. Each Mac keeps its own mascot; this tells them apart. Nil from v1.5.1 and older.
    public let home: String?
    /// How it looks: the mascot chosen on its home Mac, drawn the same on every screen it visits.
    public let look: Mascot?
    /// Set when it was thrown off the edge, so it keeps flying on the next screen.
    public let flight: RoamingFlight?

    public init(id: String, kind: RoamingKind, yFraction: Double, direction: RoamingDirection, state: RoamingState,
                home: String? = nil, look: Mascot? = nil, flight: RoamingFlight? = nil) {
        self.id = id
        self.kind = kind
        self.yFraction = yFraction.isFinite ? min(max(yFraction, 0), 1) : 1
        self.direction = direction
        self.state = state
        self.home = home
        self.look = look == Mascot.none ? nil : look
        self.flight = flight
    }

    /// An object from the network is only taken when its id is a printable token.
    public var hasValidID: Bool { PairedPeer.isValidID(id) }

    /// The edge of the receiving screen it walks in from: the opposite of the edge it left through.
    public var entryEdge: PeerSide { direction.exitEdge.opposite }
}

/// The motion of a thrown object as it crosses to the next screen. Heights are a fraction of the usable screen
/// height, because the two screens are not the same size.
public struct RoamingFlight: Codable, Sendable, Equatable {
    public static let maximumSpeed: Double = 6000

    public let liftFraction: Double
    /// Points per second; positive is right and up.
    public let vx: Double
    public let vy: Double

    public init(liftFraction: Double, vx: Double, vy: Double) {
        self.liftFraction = liftFraction.isFinite ? min(max(liftFraction, 0), 1) : 0
        self.vx = Self.clamped(vx)
        self.vy = Self.clamped(vy)
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, -maximumSpeed), maximumSpeed) : 0
    }
}
