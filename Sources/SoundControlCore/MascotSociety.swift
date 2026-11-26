import Foundation

/// How a mascot born on the desktop grows up. Founders (the ones the owner chose) are always grown.
public enum MascotGrowth {
    /// Size of a newborn, compared to a grown mascot.
    public static let babyScale = 0.55
    /// Seconds from birth to full size; only grown mascots breed.
    public static let maturity: TimeInterval = 150
    /// Seconds a born mascot stays before it wanders off for good.
    public static let lifespan: TimeInterval = 600
    /// Most mascots born and alive at once.
    public static let maximumBorn = 6

    public static func scale(age: TimeInterval) -> Double {
        babyScale + (1 - babyScale) * min(max(age / maturity, 0), 1)
    }

    public static func isAdult(age: TimeInterval) -> Bool { age >= maturity }
}

/// What the society needs to know about one mascot on the floor.
public struct MascotMember: Sendable, Equatable {
    public let id: String
    /// Middle of the mascot, in points from the left end of the screen.
    public let x: Double
    public let species: Mascot
    /// The Mac it belongs to: only two of the same Mac's animals breed.
    public let home: String?
    /// Born here and not grown yet.
    public let isBaby: Bool
    /// Walking or resting on the floor: not held, flying, running from a click or crossing an edge.
    public let isFree: Bool

    public init(id: String, x: Double, species: Mascot, home: String?, isBaby: Bool, isFree: Bool) {
        self.id = id
        self.x = x
        self.species = species
        self.home = home
        self.isBaby = isBaby
        self.isFree = isFree
    }
}

/// What one mascot should do right now, as asked by the society.
public struct MascotOrder: Sendable, Equatable {
    public enum Move: Sendable, Equatable {
        /// Carry on with its own stroll.
        case free
        /// Stand still, turned this way (nil keeps the way it faces).
        case stand(facesRight: Bool?)
        /// Walk or run towards this point (middle of the mascot).
        case go(towardX: Double, running: Bool)
    }

    public static let free = MascotOrder(move: .free, face: nil, hops: false)

    public let move: Move
    /// The sign over its head; nil leaves the usual face.
    public let face: MascotFace?
    /// Jumping for joy.
    public let hops: Bool

    public init(move: Move, face: MascotFace?, hops: Bool) {
        self.move = move
        self.face = face
        self.hops = hops
    }
}

/// A new mascot, between its two parents.
public struct MascotBirth: Sendable, Equatable {
    public let x: Double
    public let species: Mascot
    public let home: String?
}

/// The little lives of the mascots on one desktop: they nap, hop, look around, say hello, play chase, follow one
/// another, and two grown ones of a kind that spend time together can have a baby. Pure and seeded, so every rule
/// is tested without a screen; the controller only moves the mascots as ordered.
public struct MascotSociety: Sendable {
    /// Mascots farther apart than this do not notice each other.
    public static let noticeRange: Double = 600
    /// Close enough to greet, play and court.
    public static let nearRange: Double = 150
    /// A baby this far from a grown one of its kind follows it.
    static let babyFollowRange: Double = 600
    static let followGap: Double = 70
    static let playSwitch: TimeInterval = 1.3
    static let courtDuration: TimeInterval = 6

    private enum Activity: Equatable {
        case none, nap, hop, look
        case greet(String), play(String), follow(String), court(String)

        var partner: String? {
            switch self {
            case let .greet(id), let .play(id), let .follow(id), let .court(id): id
            case .none, .nap, .hop, .look: nil
            }
        }

        /// Both mascots do it together, so each must be doing it with the other.
        var isMutual: Bool {
            switch self {
            case .greet, .play, .court: true
            case .none, .nap, .hop, .look, .follow: false
            }
        }
    }

    private struct Life {
        var activity = Activity.none
        var left: TimeInterval = 0
        var elapsed: TimeInterval = 0
        /// Seconds before the next thing it decides to do.
        var rest: TimeInterval
        /// Seconds before it can have another baby.
        var love: TimeInterval = 0
    }

    private var lives: [String: Life] = [:]
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// Moves the society `dt` seconds on. Returns what each free mascot should do, and the babies born.
    /// - Parameter canBreed: false while the desktop is full.
    public mutating func step(dt: TimeInterval, members: [MascotMember], canBreed: Bool)
        -> (orders: [String: MascotOrder], births: [MascotBirth]) {
        let sorted = members.sorted { $0.id < $1.id }
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lives = lives.filter { byID[$0.key] != nil }
        for member in sorted where lives[member.id] == nil {
            lives[member.id] = Life(rest: 2 + roll() * 6)
        }
        var births: [MascotBirth] = []
        for member in sorted { births += advance(member, dt: dt, byID: byID, canBreed: canBreed) }
        for member in sorted { decide(member, byID: byID, canBreed: canBreed) }
        var orders: [String: MascotOrder] = [:]
        for member in sorted { orders[member.id] = order(for: member, byID: byID) }
        return (orders, births)
    }

    // MARK: - Doing

    private mutating func advance(_ member: MascotMember, dt: TimeInterval, byID: [String: MascotMember],
                                  canBreed: Bool) -> [MascotBirth] {
        guard var life = lives[member.id] else { return [] }
        life.love = max(0, life.love - dt)
        life.rest = max(0, life.rest - dt)
        guard member.isFree else {
            life.activity = .none
            life.rest = max(life.rest, 3)
            lives[member.id] = life
            return []
        }
        guard life.activity != .none else {
            lives[member.id] = life
            return []
        }
        life.left -= dt
        life.elapsed += dt
        var births: [MascotBirth] = []
        var isOver = life.left <= 0
        if let partnerID = life.activity.partner {
            if let partner = byID[partnerID], partner.isFree, isShared(life.activity, with: member.id, partnerID) {
                if isOver, case .court = life.activity {
                    if member.id < partnerID, canBreed {
                        births.append(MascotBirth(x: (member.x + partner.x) / 2, species: member.species,
                                                  home: member.home))
                    }
                    let cooldown = (births.isEmpty ? 60 : 150) + roll() * 150
                    life.love = cooldown
                    lives[partnerID]?.love = cooldown
                }
            } else {
                isOver = true
            }
        }
        if isOver {
            life.activity = .none
            life.elapsed = 0
            life.rest = 5 + roll() * 10
        }
        lives[member.id] = life
        return births
    }

    /// A shared activity must be mirrored by the partner; following is one-sided.
    private func isShared(_ activity: Activity, with id: String, _ partnerID: String) -> Bool {
        guard activity.isMutual else { return true }
        return lives[partnerID]?.activity.partner == id
    }

    // MARK: - Deciding

    private mutating func decide(_ member: MascotMember, byID: [String: MascotMember], canBreed: Bool) {
        guard let life = lives[member.id], member.isFree, life.activity == .none, life.rest <= 0 else { return }
        let others = byID.values.filter {
            $0.id != member.id && $0.isFree && lives[$0.id]?.activity == Activity.none
                && abs($0.x - member.x) <= Self.noticeRange
        }
        let nearest = others.min { abs($0.x - member.x) < abs($1.x - member.x) }
        if member.isBaby, let parent = nearestParent(of: member, in: byID),
           abs(parent.x - member.x) > Self.followGap + 30, roll() < 0.7 {
            begin(.follow(parent.id), for: member.id, left: 6 + roll() * 4)
        } else if let other = nearest, roll() < 0.65 {
            socialize(member, with: other, canBreed: canBreed)
        } else {
            solo(member)
        }
    }

    private func nearestParent(of baby: MascotMember, in byID: [String: MascotMember]) -> MascotMember? {
        byID.values
            .filter { !$0.isBaby && $0.isFree && $0.species == baby.species && $0.home == baby.home
                && abs($0.x - baby.x) <= Self.babyFollowRange }
            .min { abs($0.x - baby.x) < abs($1.x - baby.x) }
    }

    private mutating func socialize(_ member: MascotMember, with other: MascotMember, canBreed: Bool) {
        guard abs(other.x - member.x) <= Self.nearRange else {
            begin(.follow(other.id), for: member.id, left: 4 + roll() * 5)
            return
        }
        let canCourt = canBreed && member.species == other.species && member.home == other.home
            && !member.isBaby && !other.isBaby
            && (lives[member.id]?.love ?? 1) == 0 && (lives[other.id]?.love ?? 1) == 0
        let pick = roll()
        if canCourt, pick < 0.45 {
            begin(.court(other.id), for: member.id, left: Self.courtDuration)
            begin(.court(member.id), for: other.id, left: Self.courtDuration)
        } else if pick < 0.75 {
            let left = 2.5 + roll() * 1.5
            begin(.greet(other.id), for: member.id, left: left)
            begin(.greet(member.id), for: other.id, left: left)
        } else {
            let left = 4 + roll() * 3
            begin(.play(other.id), for: member.id, left: left)
            begin(.play(member.id), for: other.id, left: left)
        }
    }

    private mutating func solo(_ member: MascotMember) {
        let pick = roll()
        let napChance = member.isBaby ? 0.45 : 0.3
        let hopChance = member.isBaby ? 0.3 : 0.25
        if pick < napChance {
            begin(.nap, for: member.id, left: 8 + roll() * 12)
        } else if pick < napChance + hopChance {
            begin(.hop, for: member.id, left: 1.6 + roll() * 0.8)
        } else if pick < napChance + hopChance + 0.2 {
            begin(.look, for: member.id, left: 2 + roll() * 1.5)
        } else {
            let rest = 6 + roll() * 8
            lives[member.id]?.rest = rest
        }
    }

    private mutating func begin(_ activity: Activity, for id: String, left: TimeInterval) {
        lives[id]?.activity = activity
        lives[id]?.left = left
        lives[id]?.elapsed = 0
    }

    // MARK: - Ordering

    private func order(for member: MascotMember, byID: [String: MascotMember]) -> MascotOrder {
        guard member.isFree, let life = lives[member.id] else { return .free }
        func toward(_ partner: MascotMember) -> Bool { partner.x > member.x }
        switch life.activity {
        case .none:
            return .free
        case .nap:
            return MascotOrder(move: .stand(facesRight: nil), face: .sleepy, hops: false)
        case .hop:
            return MascotOrder(move: .stand(facesRight: nil), face: .happy, hops: true)
        case .look:
            return MascotOrder(move: .stand(facesRight: nil), face: .curious, hops: false)
        case let .greet(id):
            guard let partner = byID[id] else { return .free }
            return MascotOrder(move: .stand(facesRight: toward(partner)), face: .happy, hops: true)
        case let .court(id):
            guard let partner = byID[id] else { return .free }
            return MascotOrder(move: .stand(facesRight: toward(partner)), face: .love, hops: false)
        case let .play(id):
            guard let partner = byID[id] else { return .free }
            let turn = Int(life.elapsed / Self.playSwitch)
            let isChaser = turn % 2 == (member.id < id ? 0 : 1)
            let away = member.x + (member.x == partner.x ? 1 : member.x - partner.x)
            return MascotOrder(move: .go(towardX: isChaser ? partner.x : away, running: true), face: .happy, hops: false)
        case let .follow(id):
            guard let partner = byID[id] else { return .free }
            if abs(partner.x - member.x) <= Self.followGap {
                return MascotOrder(move: .stand(facesRight: toward(partner)), face: nil, hops: false)
            }
            return MascotOrder(move: .go(towardX: partner.x, running: false), face: nil, hops: false)
        }
    }

    /// A number in 0..<1 (SplitMix64).
    private mutating func roll() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
