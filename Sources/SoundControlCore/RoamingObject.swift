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
    /// Its home's colour shift in degrees, so it keeps its colour away from home. Nil from 1.6.0 and older.
    public let hue: Double?
    /// Its home's size choice, so it keeps its size away from home. Nil from 1.6.0 and older.
    public let scale: Double?

    public init(id: String, kind: RoamingKind, yFraction: Double, direction: RoamingDirection, state: RoamingState,
                home: String? = nil, look: Mascot? = nil, flight: RoamingFlight? = nil,
                hue: Double? = nil, scale: Double? = nil) {
        self.id = id
        self.kind = kind
        self.yFraction = yFraction.isFinite ? min(max(yFraction, 0), 1) : 1
        self.direction = direction
        self.state = state
        self.home = home
        self.look = look == Mascot.none ? nil : look
        self.flight = flight
        let style = MascotStyle(scale: scale ?? 1, count: 1, hue: hue ?? 0)
        self.hue = hue.map { _ in style.hue }
        self.scale = scale.map { _ in style.scale }
    }

    /// `look` is what 1.6.0 and older read, so it only ever names an animal they know; `species` is the exact one.
    private enum CodingKeys: String, CodingKey {
        case id, kind, yFraction, direction, state, home, look, species, flight, hue, scale
    }

    /// A look this computer does not know (a newer animal) falls back to the legacy look, then to no look,
    /// instead of dropping the whole object.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let species = (try? container.decodeIfPresent(String.self, forKey: .species)).flatMap { $0 }
        let legacyLook = (try? container.decodeIfPresent(Mascot.self, forKey: .look)) ?? nil
        self.init(id: try container.decode(String.self, forKey: .id),
                  kind: try container.decode(RoamingKind.self, forKey: .kind),
                  yFraction: try container.decode(Double.self, forKey: .yFraction),
                  direction: try container.decode(RoamingDirection.self, forKey: .direction),
                  state: try container.decode(RoamingState.self, forKey: .state),
                  home: try container.decodeIfPresent(String.self, forKey: .home),
                  look: species.flatMap(Mascot.init(rawValue:)) ?? legacyLook,
                  flight: try container.decodeIfPresent(RoamingFlight.self, forKey: .flight),
                  hue: (try? container.decodeIfPresent(Double.self, forKey: .hue)) ?? nil,
                  scale: (try? container.decodeIfPresent(Double.self, forKey: .scale)) ?? nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(yFraction, forKey: .yFraction)
        try container.encode(direction, forKey: .direction)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(home, forKey: .home)
        try container.encodeIfPresent(look?.legacy, forKey: .look)
        try container.encodeIfPresent(look?.rawValue, forKey: .species)
        try container.encodeIfPresent(flight, forKey: .flight)
        try container.encodeIfPresent(hue, forKey: .hue)
        try container.encodeIfPresent(scale, forKey: .scale)
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
