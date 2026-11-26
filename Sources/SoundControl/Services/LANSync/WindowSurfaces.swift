import AppKit
import CoreGraphics
import SoundControlCore

/// The other apps' windows on the main display, as surfaces a desktop mascot can climb. Reads window bounds only
/// (no titles or contents, so no screen-recording permission) and at most twice a second.
@MainActor
final class WindowSurfaces {
    private static let refreshInterval: TimeInterval = 0.5
    /// Small windows (palettes, tooltips) are not worth climbing.
    private static let minimumWidth: CGFloat = 160
    private static let minimumHeight: CGFloat = 120

    private var cached: [ClimbSurface] = []
    private var cachedArea = NSRect.zero
    private var readAt = Date.distantPast

    /// Surfaces in the coordinates of `visible` (x from its left, heights above its bottom), tops kept below
    /// `maxLift` so a mascot on a full-height window stays on screen.
    func surfaces(in visible: NSRect, maxLift: Double) -> [ClimbSurface] {
        let now = Date()
        if now.timeIntervalSince(readAt) >= Self.refreshInterval || visible != cachedArea {
            readAt = now
            cachedArea = visible
            cached = autoreleasepool { Self.read(in: visible) }
        }
        return cached.map { ClimbSurface(id: $0.id, minX: $0.minX, maxX: $0.maxX, bottom: $0.bottom,
                                         top: min($0.top, maxLift)) }
    }

    /// Front-to-back list from the window server: normal windows of other apps that are on screen.
    private static func read(in visible: NSRect) -> [ClimbSurface] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        return list.compactMap { info -> ClimbSurface? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= minimumWidth, bounds.height >= minimumHeight else { return nil }
            // Window-server bounds have their origin at the top left of the primary display.
            let frame = NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            guard frame.intersects(visible) else { return nil }
            return ClimbSurface(id: number, minX: Double(frame.minX - visible.minX), maxX: Double(frame.maxX - visible.minX),
                                bottom: Double(max(frame.minY - visible.minY, 0)),
                                top: Double(frame.maxY - visible.minY))
        }
    }
}
