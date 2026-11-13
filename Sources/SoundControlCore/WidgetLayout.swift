import Foundation

/// Pure geometry helpers for positioning and overlapping draggable widgets across any screen size.
public struct CanvasPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CanvasSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(width, 0)
        self.height = max(height, 0)
    }
}

public struct CanvasRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(center: CanvasPoint, size: CanvasSize) {
        self.minX = center.x - size.width / 2
        self.minY = center.y - size.height / 2
        self.maxX = center.x + size.width / 2
        self.maxY = center.y + size.height / 2
    }

    /// True when the interior area of both rectangles overlaps by more than a hairline.
    public func overlaps(_ other: CanvasRect) -> Bool {
        let horizontal = min(maxX, other.maxX) - max(minX, other.minX)
        let vertical = min(maxY, other.maxY) - max(minY, other.minY)
        return horizontal > 1 && vertical > 1
    }
}

public enum WidgetCanvasLayout {
    public static let edgePadding: Double = 24
    public static let clockToCardsSpacing: Double = 36
    public static let cardsSpacing: Double = 28
    public static let cornerInset: Double = 28
    public static let headerReservedTop: Double = 132
    public static let unlockReservedBottom: Double = 176

    /// Bounds within which a widget center can sit while keeping the whole widget inside the screen.
    public static func centerBounds(itemSize: CanvasSize, canvasSize: CanvasSize, padding: Double = edgePadding)
        -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let minX = min(padding + itemSize.width / 2, canvasSize.width / 2)
        let maxX = max(canvasSize.width - padding - itemSize.width / 2, canvasSize.width / 2)
        let minY = min(padding + itemSize.height / 2, canvasSize.height / 2)
        let maxY = max(canvasSize.height - padding - itemSize.height / 2, canvasSize.height / 2)
        return (minX, maxX, minY, maxY)
    }

    /// Clamps a proposed widget center so no edge of the widget leaves the canvas.
    public static func clampedCenter(_ proposed: CanvasPoint, itemSize: CanvasSize, canvasSize: CanvasSize) -> CanvasPoint {
        let b = centerBounds(itemSize: itemSize, canvasSize: canvasSize)
        return CanvasPoint(
            x: min(max(proposed.x, b.minX), b.maxX),
            y: min(max(proposed.y, b.minY), b.maxY)
        )
    }

    /// Converts a pixel center back into a screen-independent normalized point in `0...1`.
    public static func normalizedPosition(fromCenter center: CanvasPoint, itemSize: CanvasSize, canvasSize: CanvasSize) -> WidgetPosition {
        let b = centerBounds(itemSize: itemSize, canvasSize: canvasSize)
        let nx = b.maxX > b.minX ? (center.x - b.minX) / (b.maxX - b.minX) : 0.5
        let ny = b.maxY > b.minY ? (center.y - b.minY) / (b.maxY - b.minY) : 0.5
        return WidgetPosition(x: nx, y: ny)
    }

    /// Converts a normalized position into a clamped pixel center for the current screen size.
    public static func pixelCenter(from position: WidgetPosition, itemSize: CanvasSize, canvasSize: CanvasSize) -> CanvasPoint {
        let b = centerBounds(itemSize: itemSize, canvasSize: canvasSize)
        return CanvasPoint(
            x: b.minX + position.x * (b.maxX - b.minX),
            y: b.minY + position.y * (b.maxY - b.minY)
        )
    }

    /// Resolves the pixel center of an item: uses its custom normalized position when set,
    /// otherwise places it in the balanced default Smartheart Screen Saver layout.
    public static func center(
        for item: ScreenSaverItem,
        settings: ScreenSaverSettings,
        itemSize: CanvasSize,
        measuredSizes: [ScreenSaverItem: CanvasSize],
        canvasSize: CanvasSize
    ) -> CanvasPoint {
        if let custom = settings.position(for: item) {
            return pixelCenter(from: custom, itemSize: itemSize, canvasSize: canvasSize)
        }
        return clampedCenter(
            defaultCenter(for: item, settings: settings, itemSize: itemSize, measuredSizes: measuredSizes, canvasSize: canvasSize),
            itemSize: itemSize,
            canvasSize: canvasSize
        )
    }

    /// Computes which items in `order` are overlapped above/below by another visible item.
    public static func overlapStates(
        order: [ScreenSaverItem],
        rects: [ScreenSaverItem: CanvasRect]
    ) -> [ScreenSaverItem: (overlapsLower: Bool, isCoveredByUpper: Bool)] {
        var result: [ScreenSaverItem: (Bool, Bool)] = [:]
        for (index, item) in order.enumerated() {
            guard let rect = rects[item] else { continue }
            var overlapsLower = false
            for lowerIndex in 0..<index {
                let lower = order[lowerIndex]
                if let lowerRect = rects[lower], rect.overlaps(lowerRect) {
                    overlapsLower = true
                    break
                }
            }
            var isCovered = false
            for upperIndex in (index + 1)..<order.count {
                let upper = order[upperIndex]
                if let upperRect = rects[upper], rect.overlaps(upperRect) {
                    isCovered = true
                    break
                }
            }
            result[item] = (overlapsLower, isCovered)
        }
        return result
    }

    private static func defaultCenter(
        for item: ScreenSaverItem,
        settings: ScreenSaverSettings,
        itemSize: CanvasSize,
        measuredSizes: [ScreenSaverItem: CanvasSize],
        canvasSize: CanvasSize
    ) -> CanvasPoint {
        if item == .sessions {
            let corner = settings.sessionsCorner
            let x = corner.isLeft
                ? cornerInset + itemSize.width / 2
                : canvasSize.width - cornerInset - itemSize.width / 2
            let y = corner.isTop
                ? cornerInset + itemSize.height / 2
                : canvasSize.height - cornerInset - itemSize.height / 2
            return CanvasPoint(x: x, y: y)
        }

        let showClock = settings.shows(.clock)
        let showCalendar = settings.shows(.calendar)
        let showUsage = settings.shows(.claudeUsage)

        let clockSize = measuredSizes[.clock] ?? (item == .clock ? itemSize : CanvasSize(width: 320, height: 170))
        let calendarSize = measuredSizes[.calendar] ?? (item == .calendar ? itemSize : CanvasSize(width: 280, height: 270))
        let usageSize = measuredSizes[.claudeUsage] ?? (item == .claudeUsage ? itemSize : CanvasSize(width: 270, height: 200))

        let hasRow = showCalendar || showUsage
        let rowHeight = max(showCalendar ? calendarSize.height : 0, showUsage ? usageSize.height : 0)
        let blockHeight: Double =
            (showClock ? clockSize.height : 0)
            + (showClock && hasRow ? clockToCardsSpacing : 0)
            + (hasRow ? rowHeight : 0)

        let safeTop = headerReservedTop
        let safeBottom = max(canvasSize.height - unlockReservedBottom, safeTop + blockHeight)
        let middleCenterY = (safeTop + safeBottom) / 2
        let blockTopY = max(safeTop, middleCenterY - blockHeight / 2)

        switch item {
        case .clock:
            return CanvasPoint(x: canvasSize.width / 2, y: blockTopY + clockSize.height / 2)
        case .calendar, .claudeUsage:
            let rowTopY = blockTopY + (showClock ? clockSize.height + clockToCardsSpacing : 0)
            if showCalendar && showUsage {
                let rowWidth = calendarSize.width + cardsSpacing + usageSize.width
                let startX = (canvasSize.width - rowWidth) / 2
                if item == .calendar {
                    return CanvasPoint(x: startX + calendarSize.width / 2, y: rowTopY + calendarSize.height / 2)
                } else {
                    return CanvasPoint(x: startX + calendarSize.width + cardsSpacing + usageSize.width / 2, y: rowTopY + usageSize.height / 2)
                }
            }
            return CanvasPoint(x: canvasSize.width / 2, y: rowTopY + itemSize.height / 2)
        case .sessions:
            return CanvasPoint(x: canvasSize.width / 2, y: middleCenterY)
        }
    }
}
