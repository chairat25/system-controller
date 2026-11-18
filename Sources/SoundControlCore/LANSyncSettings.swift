import Foundation

/// Which edge of this Mac's screen a paired Mac sits beyond.
public enum PeerSide: String, Codable, Sendable, CaseIterable, Identifiable {
    case left, right

    public var id: String { rawValue }
    public var opposite: PeerSide { self == .left ? .right : .left }

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// A Mac this one has paired with. The shared key lives in a key file, never here.
public struct PairedPeer: Codable, Sendable, Equatable, Identifiable {
    /// Written in place of a side for a Mac that is not beside this one (it shares wallpapers only).
    static let notBeside = "none"

    public static let maximumNameLength = 60
    public static let maximumIDLength = 64

    public let id: String
    public let name: String
    /// The edge it sits beyond, or nil when it is not next to this Mac. With three Macs in a row the outer two
    /// are not beside each other, so a mascot reaching the free edge turns back.
    public let side: PeerSide?

    public init(id: String, name: String, side: PeerSide?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = trimmed.isEmpty ? "Mac" : String(trimmed.prefix(Self.maximumNameLength))
        self.side = side
    }

    /// A device id is a short, printable token. Anything else is not accepted from the network or from disk.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= maximumIDLength
            && id.unicodeScalars.allSatisfy { $0.isASCII && !CharacterSet.controlCharacters.contains($0) && $0 != " " }
    }

    /// An entry with a bad id or side is dropped by the caller instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard Self.isValidID(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid peer id")
        }
        let rawSide = try? container.decode(String.self, forKey: .side)
        self.init(id: id,
                  name: (try? container.decode(String.self, forKey: .name)) ?? "Mac",
                  side: rawSide == Self.notBeside ? nil : rawSide.flatMap(PeerSide.init(rawValue:)) ?? .right)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(side?.rawValue ?? Self.notBeside, forKey: .side)
    }

    private enum CodingKeys: String, CodingKey { case id, name, side }
}

/// What LAN sync shares and with whom. Stored as JSON next to `config.json`.
public struct LANSyncSettings: Codable, Sendable, Equatable {
    public static let maximumPeers = 8
    public static let `default` = LANSyncSettings(isWallpaperSyncOn: false, isMascotRoamingOn: false, pairedPeers: [])

    /// Shares the screen saver background and the desktop wallpaper with paired Macs.
    public let isWallpaperSyncOn: Bool
    /// Lets the desktop mascot walk off a screen edge and appear on a paired Mac.
    public let isMascotRoamingOn: Bool
    public let pairedPeers: [PairedPeer]

    /// True while anything needs the network: the app listens and browses only then.
    public var isActive: Bool { isWallpaperSyncOn || isMascotRoamingOn }

    public init(isWallpaperSyncOn: Bool, isMascotRoamingOn: Bool, pairedPeers: [PairedPeer]) {
        self.isWallpaperSyncOn = isWallpaperSyncOn
        self.isMascotRoamingOn = isMascotRoamingOn
        var seen = Set<String>()
        self.pairedPeers = Array(pairedPeers.filter { seen.insert($0.id).inserted }.prefix(Self.maximumPeers))
    }

    /// Missing or unreadable fields fall back to defaults instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        self.init(
            isWallpaperSyncOn: (try? container.decodeIfPresent(Bool.self, forKey: .isWallpaperSyncOn)) ?? nil
                ?? fallback.isWallpaperSyncOn,
            isMascotRoamingOn: (try? container.decodeIfPresent(Bool.self, forKey: .isMascotRoamingOn)) ?? nil
                ?? fallback.isMascotRoamingOn,
            pairedPeers: container.decodeLossyArray(PairedPeer.self, forKey: .pairedPeers) ?? [])
    }

    public func peer(id: String) -> PairedPeer? { pairedPeers.first { $0.id == id } }
    public func peer(on side: PeerSide) -> PairedPeer? { pairedPeers.first { $0.side == side } }
    public func isPaired(_ id: String) -> Bool { peer(id: id) != nil }

    public func withWallpaperSync(_ value: Bool) -> Self { copy(isWallpaperSyncOn: value) }
    public func withMascotRoaming(_ value: Bool) -> Self { copy(isMascotRoamingOn: value) }

    /// Adds a peer, or replaces its name when it is already paired (the chosen side is kept).
    public func adding(_ peer: PairedPeer) -> Self {
        guard let existing = self.peer(id: peer.id) else { return copy(pairedPeers: pairedPeers + [peer]) }
        return copy(pairedPeers: pairedPeers.map { $0.id == peer.id ? PairedPeer(id: peer.id, name: peer.name, side: existing.side) : $0 })
    }

    public func removing(_ id: String) -> Self {
        copy(pairedPeers: pairedPeers.filter { $0.id != id })
    }

    /// Puts a Mac beyond an edge, or nowhere. Only one Mac sits beyond each edge: the one that held it before
    /// is moved off it.
    public func withSide(_ side: PeerSide?, for id: String) -> Self {
        copy(pairedPeers: pairedPeers.map { peer in
            if peer.id == id { return PairedPeer(id: peer.id, name: peer.name, side: side) }
            if side != nil, peer.side == side { return PairedPeer(id: peer.id, name: peer.name, side: nil) }
            return peer
        })
    }

    /// The side a newly paired Mac takes: a free edge, right first, else none.
    public var freeSide: PeerSide? {
        [PeerSide.right, .left].first { peer(on: $0) == nil }
    }

    /// One place that lists every field, so each `with` method changes just its own.
    private func copy(isWallpaperSyncOn: Bool? = nil, isMascotRoamingOn: Bool? = nil,
                      pairedPeers: [PairedPeer]? = nil) -> Self {
        Self(isWallpaperSyncOn: isWallpaperSyncOn ?? self.isWallpaperSyncOn,
             isMascotRoamingOn: isMascotRoamingOn ?? self.isMascotRoamingOn,
             pairedPeers: pairedPeers ?? self.pairedPeers)
    }

    private enum CodingKeys: String, CodingKey {
        case isWallpaperSyncOn, isMascotRoamingOn, pairedPeers
    }
}
