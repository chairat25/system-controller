import Foundation

/// Rules for taking a wallpaper from another Mac.
public enum WallpaperSyncPolicy {
    public static let maximumBytes = 20 * 1024 * 1024

    public enum Decision: Equatable, Sendable {
        case accept
        case notNewer
        case tooLarge
        case invalid
    }

    /// Whether to take `meta` when the local wallpaper of that kind dates from `localTimestamp` (nil for none).
    /// Equal timestamps are not newer, which is what stops two Macs passing one wallpaper back and forth.
    public static func decision(for meta: WallpaperMeta, localTimestamp: Double?) -> Decision {
        guard meta.timestamp.isFinite, meta.timestamp > 0, meta.size > 0 else { return .invalid }
        guard meta.size <= maximumBytes else { return .tooLarge }
        guard let localTimestamp else { return .accept }
        return meta.timestamp > localTimestamp ? .accept : .notNewer
    }

    /// A send is dropped when a newer wallpaper of the same kind has been chosen since it was queued.
    public static func isSuperseded(queued timestamp: Double, latest: Double?) -> Bool {
        guard let latest else { return false }
        return latest > timestamp
    }
}

/// The wallpaper every paired Mac converges on: for each kind, the moment the current one was chosen,
/// on any Mac. Whoever holds the older moment pulls the newer wallpaper, so the group agrees on the newest.
public struct WallpaperSyncState: Sendable, Equatable {
    public let timestamps: [WallpaperKind: Double]

    public init(timestamps: [WallpaperKind: Double] = [:]) {
        self.timestamps = timestamps.filter { $0.value.isFinite && $0.value > 0 }
    }

    public func timestamp(of kind: WallpaperKind) -> Double? { timestamps[kind] }

    /// Answer to a peer's offer: pull it only when it is newer than what this Mac has.
    public func decision(for offer: WallpaperMeta) -> WallpaperSyncPolicy.Decision {
        WallpaperSyncPolicy.decision(for: offer, localTimestamp: timestamp(of: offer.kind))
    }

    /// The state after this Mac chose a wallpaper, or took one from a peer. Never moves backwards.
    public func recording(_ kind: WallpaperKind, at timestamp: Double) -> Self {
        guard timestamp.isFinite, timestamp > (self.timestamp(of: kind) ?? 0) else { return self }
        var next = timestamps
        next[kind] = timestamp
        return Self(timestamps: next)
    }
}
