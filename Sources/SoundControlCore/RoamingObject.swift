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

    public init(id: String, kind: RoamingKind, yFraction: Double, direction: RoamingDirection, state: RoamingState) {
        self.id = id
        self.kind = kind
        self.yFraction = yFraction.isFinite ? min(max(yFraction, 0), 1) : 1
        self.direction = direction
        self.state = state
    }

    /// An object from the network is only taken when its id is a printable token.
    public var hasValidID: Bool { PairedPeer.isValidID(id) }

    /// The edge of the receiving screen it walks in from: the opposite of the edge it left through.
    public var entryEdge: PeerSide { direction.exitEdge.opposite }
}
