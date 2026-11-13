import Foundation

/// Which way the fingers moved on the trackpad.
public enum SwipeDirection: Sendable, Equatable {
    case left, right
}

/// Adds up one two-finger scroll gesture and decides whether it was a sideways swipe.
public struct SwipeTracker: Sendable, Equatable {
    /// Points the fingers must travel sideways before it counts, so a resting hand does nothing.
    public static let minimumDistance: Double = 60

    public static let initial = SwipeTracker(dx: 0, dy: 0)

    public let dx: Double
    public let dy: Double

    public func adding(dx: Double, dy: Double) -> Self {
        Self(dx: self.dx + dx, dy: self.dy + dy)
    }

    /// Sideways and far enough; a mostly vertical stroke is a scroll, not a swipe.
    public var direction: SwipeDirection? {
        guard abs(dx) >= Self.minimumDistance, abs(dx) > abs(dy) * 1.5 else { return nil }
        return dx > 0 ? .right : .left
    }

    /// Scroll deltas follow the content; with natural scrolling off they point against the fingers.
    public static func fingerDelta(scrollDelta: Double, isNatural: Bool) -> Double {
        isNatural ? scrollDelta : -scrollDelta
    }
}

/// The settings drawers on the screen saver. Each slides in from its own edge, following the fingers,
/// so the dimming drawer sits on the left, away from the Notification Center on the right.
public enum ScreenSaverDrawer: Sendable, Equatable {
    case closed
    /// Left edge: when and how far the screen dims.
    case dimming
    /// Right edge: what shows and what stays lit.
    case widgets

    public func after(_ swipe: SwipeDirection) -> Self {
        switch (self, swipe) {
        case (.closed, .right): .dimming
        case (.closed, .left): .widgets
        case (.dimming, .left), (.widgets, .right): .closed
        default: self
        }
    }
}

/// Stepping through a fixed list of choices with plus and minus buttons, where a menu cannot open.
public enum Presets {
    /// The next preset in that direction; a value between presets moves to the nearest one on that side.
    public static func step(_ presets: [Int], from current: Int, by delta: Int) -> Int {
        let sorted = presets.sorted()
        if delta > 0 { return sorted.first { $0 > current } ?? sorted.last ?? current }
        if delta < 0 { return sorted.last { $0 < current } ?? sorted.first ?? current }
        return current
    }
}
