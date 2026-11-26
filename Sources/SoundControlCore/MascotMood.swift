import Foundation

/// The face a mascot makes.
public enum MascotFace: Sendable, Equatable {
    case calm
    /// First poke: "hm?"
    case curious
    /// Poked again: "??"
    case veryCurious
    /// Keeps getting poked.
    case annoyed
    /// Had enough: runs away.
    case fleeing
    /// Dozing off.
    case sleepy
    /// Playing or saying hello.
    case happy
    /// Close to a friend of its own kind.
    case love
}

/// How a mascot feels about being clicked. Clicks close together build up from curious to annoyed, and enough of
/// them make it run away; left alone for a few seconds it calms down again. Pure value, so the steps are tested.
public struct MascotMood: Sendable, Equatable {
    /// A click this soon after the last one adds to the streak; a later one starts over.
    public static let streakGap: TimeInterval = 2.5
    /// How long a face stays after the last click.
    public static let faceDuration: TimeInterval = 4
    /// Clicks in a row that make it run away.
    public static let fleeClicks = 6
    static let annoyedClicks = 3

    public static let calm = MascotMood(clicks: 0, lastClick: -.infinity)

    public let clicks: Int
    /// Time of the last click, in seconds on any steady clock.
    public let lastClick: TimeInterval

    public func poked(at time: TimeInterval) -> MascotMood {
        let continues = time - lastClick <= Self.streakGap
        return MascotMood(clicks: continues ? clicks + 1 : 1, lastClick: time)
    }

    /// True right after the click that makes it run; each further click while the streak lasts keeps it running.
    public var wantsToFlee: Bool { clicks >= Self.fleeClicks }

    public func face(at time: TimeInterval) -> MascotFace {
        guard clicks > 0, time - lastClick < Self.faceDuration else { return .calm }
        switch clicks {
        case 1: return .curious
        case 2: return .veryCurious
        case ..<Self.fleeClicks: return .annoyed
        default: return .fleeing
        }
    }
}
