import Foundation

/// Something the screen saver can show. Order of `allCases` is the order on screen.
public enum ScreenSaverWidget: String, Codable, Sendable, CaseIterable, Identifiable {
    case clock
    case calendar
    case claudeUsage

    public var id: String { rawValue }
}

/// Draggable item on the Smartheart Screen Saver canvas, including widgets and the live Claude sessions card.
public enum ScreenSaverItem: String, Codable, Sendable, CaseIterable, Identifiable {
    case clock
    case calendar
    case claudeUsage
    case sessions

    public var id: String { rawValue }
}

/// Normalized center position (`0...1` on each axis of the screen saver canvas).
public struct WidgetPosition: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }
}

/// A corner of the screen, for the Claude sessions list.
public enum ScreenSaverCorner: String, Codable, Sendable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var id: String { rawValue }
    public var isTop: Bool { self == .topLeft || self == .topRight }
    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
}

/// Backdrop behind the widgets and mascot on the Smartheart Screen Saver.
public enum ScreenSaverBackground: String, Codable, Sendable, CaseIterable, Identifiable {
    case pitchBlack
    case midnight
    case aurora
    case ember
    case ocean
    case forest
    case cosmos
    case desktopWallpaper
    case customImage

    public static let presets: [ScreenSaverBackground] = allCases.filter { $0 != .customImage }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pitchBlack: "Pitch Black"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .cosmos: "Cosmos"
        case .desktopWallpaper: "Mac Wallpaper"
        case .customImage: "Custom Photo"
        }
    }
}

/// What the owner-lock screen saver shows and how it dims. Stored as JSON next to `config.json`.
public struct ScreenSaverSettings: Codable, Sendable, Equatable {
    public static let minimumDimAfter = 10
    public static let maximumDimAfter = 3600
    public static let maximumFade = 3600
    public static let maximumPins = 20
    public static let `default` = ScreenSaverSettings(widgets: [.clock, .calendar, .claudeUsage],
                                                      isDimEnabled: true, dimAfterSeconds: 60,
                                                      dimLevel: 0, fadeSeconds: 120)

    public let widgets: [ScreenSaverWidget]
    public let isDimEnabled: Bool
    /// Idle time before dimming starts.
    public let dimAfterSeconds: Int
    /// Brightness reached at the end of the fade: 1 is full, 0 is no light at all.
    public let dimLevel: Double
    /// How long the fade from full brightness to `dimLevel` takes. 0 jumps straight to `dimLevel`.
    public let fadeSeconds: Int
    /// Global shortcut that starts the screen saver, nil when none is set.
    public let shortcut: KeyShortcut?
    /// Lists the Claude sessions that are working, in the corner `sessionsCorner`.
    public let showsSessions: Bool
    /// Which corner the Claude sessions list sits in.
    public let sessionsCorner: ScreenSaverCorner
    /// Sessions that stay listed after they stop working, newest last.
    public let pinnedSessionIDs: [String]
    /// Keeps the clock lit at `clockLevel` while everything else dims.
    public let isClockBright: Bool
    public let clockLevel: Double
    /// The animal that strolls along the bottom of the main display, `.none` for no mascot.
    public let mascot: Mascot
    /// Explicitly hides the mascot without forgetting the chosen animal.
    public let isMascotHidden: Bool
    /// Keeps the mascot lit at `mascotLevel` while everything else dims, so it can still be seen playing.
    public let isMascotBright: Bool
    public let mascotLevel: Double
    /// Backdrop behind the widgets and mascot.
    public let background: ScreenSaverBackground
    /// Display name of the user-selected custom photo, nil when none is set.
    public let customBackgroundName: String?
    /// Custom normalized center coordinates per `ScreenSaverItem.rawValue`.
    public let widgetPositions: [String: WidgetPosition]
    /// Bottom-to-top Z-stacking order of screen saver items (last item sits topmost).
    public let widgetOrder: [ScreenSaverItem]

    /// The mascot shown on the screen saver (`.none` when hidden).
    public var activeMascot: Mascot {
        isMascotHidden ? .none : mascot
    }

    public var hasCustomWidgetLayout: Bool {
        !widgetPositions.isEmpty || widgetOrder != ScreenSaverItem.allCases
    }

    public init(widgets: [ScreenSaverWidget], isDimEnabled: Bool, dimAfterSeconds: Int,
                dimLevel: Double, fadeSeconds: Int, shortcut: KeyShortcut? = nil,
                showsSessions: Bool = true, sessionsCorner: ScreenSaverCorner = .topLeft,
                pinnedSessionIDs: [String] = [],
                isClockBright: Bool = false, clockLevel: Double = 1, mascot: Mascot = .cat,
                isMascotHidden: Bool = false,
                isMascotBright: Bool = false, mascotLevel: Double = 1,
                background: ScreenSaverBackground = .pitchBlack, customBackgroundName: String? = nil,
                widgetPositions: [String: WidgetPosition] = [:],
                widgetOrder: [ScreenSaverItem] = ScreenSaverItem.allCases) {
        // Rebuilt from `allCases` so the order is fixed and a widget can never appear twice.
        self.widgets = ScreenSaverWidget.allCases.filter(widgets.contains)
        self.isDimEnabled = isDimEnabled
        self.dimAfterSeconds = min(max(dimAfterSeconds, Self.minimumDimAfter), Self.maximumDimAfter)
        self.dimLevel = Self.unit(dimLevel, fallback: 0)
        self.fadeSeconds = min(max(fadeSeconds, 0), Self.maximumFade)
        self.shortcut = shortcut
        self.showsSessions = showsSessions
        self.sessionsCorner = sessionsCorner
        var seen = Set<String>()
        self.pinnedSessionIDs = Array(pinnedSessionIDs.filter { seen.insert($0).inserted }.suffix(Self.maximumPins))
        self.isClockBright = isClockBright
        self.clockLevel = Self.unit(clockLevel, fallback: 1)
        self.mascot = mascot
        self.isMascotHidden = isMascotHidden
        self.isMascotBright = isMascotBright
        self.mascotLevel = Self.unit(mascotLevel, fallback: 1)
        let trimmedName = customBackgroundName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customBackgroundName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        self.background = background
        let validKeys = Set(ScreenSaverItem.allCases.map(\.rawValue))
        self.widgetPositions = widgetPositions.filter { validKeys.contains($0.key) }
        self.widgetOrder = Self.normalizedOrder(widgetOrder)
    }

    /// Missing or out-of-range fields fall back to defaults instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        self.init(
            widgets: try container.decodeIfPresent([ScreenSaverWidget].self, forKey: .widgets) ?? fallback.widgets,
            isDimEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDimEnabled) ?? fallback.isDimEnabled,
            dimAfterSeconds: try container.decodeIfPresent(Int.self, forKey: .dimAfterSeconds) ?? fallback.dimAfterSeconds,
            dimLevel: try container.decodeIfPresent(Double.self, forKey: .dimLevel) ?? fallback.dimLevel,
            fadeSeconds: try container.decodeIfPresent(Int.self, forKey: .fadeSeconds) ?? fallback.fadeSeconds,
            // An unusable shortcut is dropped instead of failing the whole file.
            shortcut: try? container.decodeIfPresent(KeyShortcut.self, forKey: .shortcut),
            showsSessions: try container.decodeIfPresent(Bool.self, forKey: .showsSessions) ?? fallback.showsSessions,
            // An unknown corner name falls back to the default instead of failing the whole file.
            sessionsCorner: (try? container.decodeIfPresent(ScreenSaverCorner.self, forKey: .sessionsCorner)) ?? nil
                ?? fallback.sessionsCorner,
            pinnedSessionIDs: try container.decodeIfPresent([String].self, forKey: .pinnedSessionIDs) ?? [],
            isClockBright: try container.decodeIfPresent(Bool.self, forKey: .isClockBright) ?? fallback.isClockBright,
            clockLevel: try container.decodeIfPresent(Double.self, forKey: .clockLevel) ?? fallback.clockLevel,
            // An unknown animal falls back to the default instead of failing the whole file.
            mascot: (try? container.decodeIfPresent(Mascot.self, forKey: .mascot)) ?? nil ?? fallback.mascot,
            isMascotHidden: try container.decodeIfPresent(Bool.self, forKey: .isMascotHidden) ?? fallback.isMascotHidden,
            isMascotBright: try container.decodeIfPresent(Bool.self, forKey: .isMascotBright) ?? fallback.isMascotBright,
            mascotLevel: try container.decodeIfPresent(Double.self, forKey: .mascotLevel) ?? fallback.mascotLevel,
            // An unknown background falls back to pitch black instead of failing the whole file.
            background: (try? container.decodeIfPresent(ScreenSaverBackground.self, forKey: .background)) ?? nil
                ?? fallback.background,
            customBackgroundName: try? container.decodeIfPresent(String.self, forKey: .customBackgroundName),
            widgetPositions: (try? container.decodeIfPresent([String: WidgetPosition].self, forKey: .widgetPositions)) ?? [:],
            widgetOrder: (try? container.decodeIfPresent([ScreenSaverItem].self, forKey: .widgetOrder)) ?? ScreenSaverItem.allCases)
    }

    public func shows(_ widget: ScreenSaverWidget) -> Bool {
        widgets.contains(widget)
    }

    public func isPinned(_ sessionID: String) -> Bool {
        pinnedSessionIDs.contains(sessionID)
    }

    public func position(for item: ScreenSaverItem) -> WidgetPosition? {
        widgetPositions[item.rawValue]
    }

    public func zIndex(of item: ScreenSaverItem) -> Int {
        widgetOrder.firstIndex(of: item) ?? 0
    }

    public func showing(_ widget: ScreenSaverWidget, _ isShown: Bool) -> Self {
        copy(widgets: isShown ? widgets + [widget] : widgets.filter { $0 != widget })
    }

    public func withDimEnabled(_ value: Bool) -> Self { copy(isDimEnabled: value) }
    public func withDimAfter(seconds: Int) -> Self { copy(dimAfterSeconds: seconds) }
    public func withDimLevel(_ value: Double) -> Self { copy(dimLevel: value) }
    public func withFade(seconds: Int) -> Self { copy(fadeSeconds: seconds) }
    public func withShortcut(_ value: KeyShortcut?) -> Self { copy(shortcut: .some(value)) }
    public func withShowsSessions(_ value: Bool) -> Self { copy(showsSessions: value) }
    public func withSessionsCorner(_ value: ScreenSaverCorner) -> Self {
        var nextPositions = widgetPositions
        nextPositions.removeValue(forKey: ScreenSaverItem.sessions.rawValue)
        return copy(sessionsCorner: value, widgetPositions: nextPositions)
    }

    public func moving(_ item: ScreenSaverItem, to position: WidgetPosition) -> Self {
        var nextPositions = widgetPositions
        nextPositions[item.rawValue] = position
        return copy(widgetPositions: nextPositions, widgetOrder: Self.promoting(item, in: widgetOrder))
    }

    public func bringingToFront(_ item: ScreenSaverItem) -> Self {
        copy(widgetOrder: Self.promoting(item, in: widgetOrder))
    }

    public func resetWidgetLayout() -> Self {
        copy(widgetPositions: [:], widgetOrder: ScreenSaverItem.allCases)
    }
    public func withClockBright(_ value: Bool) -> Self { copy(isClockBright: value) }
    public func withClockLevel(_ value: Double) -> Self { copy(clockLevel: value) }
    public func withMascot(_ value: Mascot) -> Self {
        copy(mascot: value, isMascotHidden: value == .none)
    }

    public func withMascotHidden(_ isHidden: Bool) -> Self {
        if isHidden {
            return copy(isMascotHidden: true)
        }
        let restored: Mascot = mascot == .none ? .cat : mascot
        return copy(mascot: restored, isMascotHidden: false)
    }
    public func withMascotBright(_ value: Bool) -> Self { copy(isMascotBright: value) }
    public func withMascotLevel(_ value: Double) -> Self { copy(mascotLevel: value) }
    public func withBackground(_ value: ScreenSaverBackground) -> Self { copy(background: value) }

    public func withCustomBackground(name: String?) -> Self {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return copy(background: background == .customImage ? .pitchBlack : background,
                        customBackgroundName: .some(nil))
        }
        return copy(background: .customImage, customBackgroundName: .some(trimmed))
    }

    public func pinning(_ sessionID: String, _ isPinned: Bool) -> Self {
        let others = pinnedSessionIDs.filter { $0 != sessionID }
        return copy(pinnedSessionIDs: isPinned ? others + [sessionID] : others)
    }

    /// Screen brightness after `idle` seconds without activity: 1 until `dimAfterSeconds`,
    /// then a straight line down to `dimLevel` over `fadeSeconds`.
    public func brightness(idle: TimeInterval) -> Double {
        guard isDimEnabled else { return 1 }
        let sinceDimStart = idle - TimeInterval(dimAfterSeconds)
        guard sinceDimStart > 0 else { return 1 }
        guard fadeSeconds > 0 else { return dimLevel }
        let progress = min(sinceDimStart / TimeInterval(fadeSeconds), 1)
        return 1 + (dimLevel - 1) * progress
    }

    /// The clock follows the screen as it dims, then holds at `clockLevel` when it is kept lit.
    public func clockBrightness(screen: Double) -> Double {
        isClockBright ? max(screen, clockLevel) : screen
    }

    /// The mascot follows the screen as it dims, then holds at `mascotLevel` when it is kept lit.
    public func mascotBrightness(screen: Double) -> Double {
        isMascotBright ? max(screen, mascotLevel) : screen
    }

    private static func unit(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : fallback
    }

    private static func normalizedOrder(_ order: [ScreenSaverItem]) -> [ScreenSaverItem] {
        var seen = Set<ScreenSaverItem>()
        let filtered = order.filter { seen.insert($0).inserted }
        let missing = ScreenSaverItem.allCases.filter { !seen.contains($0) }
        return filtered + missing
    }

    private static func promoting(_ item: ScreenSaverItem, in order: [ScreenSaverItem]) -> [ScreenSaverItem] {
        normalizedOrder(order.filter { $0 != item } + [item])
    }

    /// One place that lists every field, so each `with` method changes just its own.
    private func copy(widgets: [ScreenSaverWidget]? = nil, isDimEnabled: Bool? = nil, dimAfterSeconds: Int? = nil,
                      dimLevel: Double? = nil, fadeSeconds: Int? = nil, shortcut: KeyShortcut?? = nil,
                      showsSessions: Bool? = nil, sessionsCorner: ScreenSaverCorner? = nil, pinnedSessionIDs: [String]? = nil,
                      isClockBright: Bool? = nil, clockLevel: Double? = nil, mascot: Mascot? = nil,
                      isMascotHidden: Bool? = nil, isMascotBright: Bool? = nil, mascotLevel: Double? = nil,
                      background: ScreenSaverBackground? = nil, customBackgroundName: String?? = nil,
                      widgetPositions: [String: WidgetPosition]? = nil,
                      widgetOrder: [ScreenSaverItem]? = nil) -> Self {
        Self(widgets: widgets ?? self.widgets, isDimEnabled: isDimEnabled ?? self.isDimEnabled,
             dimAfterSeconds: dimAfterSeconds ?? self.dimAfterSeconds, dimLevel: dimLevel ?? self.dimLevel,
             fadeSeconds: fadeSeconds ?? self.fadeSeconds, shortcut: shortcut ?? self.shortcut,
             showsSessions: showsSessions ?? self.showsSessions, sessionsCorner: sessionsCorner ?? self.sessionsCorner,
             pinnedSessionIDs: pinnedSessionIDs ?? self.pinnedSessionIDs,
             isClockBright: isClockBright ?? self.isClockBright, clockLevel: clockLevel ?? self.clockLevel,
             mascot: mascot ?? self.mascot, isMascotHidden: isMascotHidden ?? self.isMascotHidden,
             isMascotBright: isMascotBright ?? self.isMascotBright,
             mascotLevel: mascotLevel ?? self.mascotLevel,
             background: background ?? self.background,
             customBackgroundName: customBackgroundName ?? self.customBackgroundName,
             widgetPositions: widgetPositions ?? self.widgetPositions,
             widgetOrder: widgetOrder ?? self.widgetOrder)
    }

    private enum CodingKeys: String, CodingKey {
        case widgets, isDimEnabled, dimAfterSeconds, dimLevel, fadeSeconds, shortcut
        case showsSessions, sessionsCorner, pinnedSessionIDs, isClockBright, clockLevel, mascot
        case isMascotHidden, isMascotBright, mascotLevel, background, customBackgroundName
        case widgetPositions, widgetOrder
    }
}
