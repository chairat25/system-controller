import Foundation

/// How this Mac's own desktop mascots look and how many there are. Kept on this Mac only.
public struct MascotStyle: Equatable, Sendable {
    public static let scaleRange: ClosedRange<Double> = 0.75...2.0
    public static let countRange: ClosedRange<Int> = 1...6
    public static let `default` = MascotStyle(scale: 1, count: 1, hue: 0)

    /// Size relative to the normal one.
    public let scale: Double
    /// How many of this Mac's own animal walk around.
    public let count: Int
    /// Colour shift in degrees, 0 for the animal's own colours.
    public let hue: Double

    public init(scale: Double, count: Int, hue: Double) {
        self.scale = min(max(scale.isFinite ? scale : 1, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        self.count = min(max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
        let wrapped = (hue.isFinite ? hue : 0).truncatingRemainder(dividingBy: 360)
        self.hue = wrapped < 0 ? wrapped + 360 : wrapped
    }

    public var isRecoloured: Bool { hue != 0 }
}

/// Settings for the whole app, not one module. Stored as JSON next to `config.json`.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let `default` = AppSettings(popupShortcut: nil, autoUpdateEnabled: false)

    /// Global shortcut that opens the menu-bar popup on the Control tab, nil when none is set.
    public let popupShortcut: KeyShortcut?

    /// Automatically check GitHub Releases and install updates in the background.
    public let autoUpdateEnabled: Bool

    /// Frame rate of a held or thrown desktop mascot on this Mac.
    public let throwFrameRate: ThrowFrameRate

    /// Language of the app's own screens.
    public let language: AppLanguage

    /// Size, number and colour of this Mac's desktop mascots.
    public let mascotStyle: MascotStyle

    /// Whether the app runs lighter when the Mac is hot, short of memory or busy.
    public let resourceSaving: ResourceSaving

    public init(popupShortcut: KeyShortcut?, autoUpdateEnabled: Bool = false,
                throwFrameRate: ThrowFrameRate = .default, language: AppLanguage = .default,
                mascotStyle: MascotStyle = .default, resourceSaving: ResourceSaving = .default) {
        self.popupShortcut = popupShortcut
        self.autoUpdateEnabled = autoUpdateEnabled
        self.throwFrameRate = throwFrameRate
        self.language = language
        self.mascotStyle = mascotStyle
        self.resourceSaving = resourceSaving
    }

    /// An unusable shortcut is dropped instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let style = MascotStyle(
            scale: (try? container.decodeIfPresent(Double.self, forKey: .mascotScale)) ?? MascotStyle.default.scale,
            count: (try? container.decodeIfPresent(Int.self, forKey: .mascotCount)) ?? MascotStyle.default.count,
            hue: (try? container.decodeIfPresent(Double.self, forKey: .mascotHue)) ?? MascotStyle.default.hue)
        self.init(
            popupShortcut: try? container.decodeIfPresent(KeyShortcut.self, forKey: .popupShortcut),
            autoUpdateEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled)) ?? false,
            throwFrameRate: (try? container.decodeIfPresent(ThrowFrameRate.self, forKey: .throwFrameRate)) ?? .default,
            language: (try? container.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? .default,
            mascotStyle: style,
            resourceSaving: (try? container.decodeIfPresent(ResourceSaving.self, forKey: .resourceSaving)) ?? .default)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(popupShortcut, forKey: .popupShortcut)
        try container.encode(autoUpdateEnabled, forKey: .autoUpdateEnabled)
        try container.encode(throwFrameRate, forKey: .throwFrameRate)
        try container.encode(language, forKey: .language)
        try container.encode(mascotStyle.scale, forKey: .mascotScale)
        try container.encode(mascotStyle.count, forKey: .mascotCount)
        try container.encode(mascotStyle.hue, forKey: .mascotHue)
        try container.encode(resourceSaving, forKey: .resourceSaving)
    }

    public func withPopupShortcut(_ value: KeyShortcut?) -> Self {
        Self(popupShortcut: value, autoUpdateEnabled: autoUpdateEnabled, throwFrameRate: throwFrameRate,
             language: language, mascotStyle: mascotStyle, resourceSaving: resourceSaving)
    }

    public func withAutoUpdate(_ value: Bool) -> Self {
        guard value != autoUpdateEnabled else { return self }
        return Self(popupShortcut: popupShortcut, autoUpdateEnabled: value, throwFrameRate: throwFrameRate,
                    language: language, mascotStyle: mascotStyle, resourceSaving: resourceSaving)
    }

    public func withThrowFrameRate(_ value: ThrowFrameRate) -> Self {
        Self(popupShortcut: popupShortcut, autoUpdateEnabled: autoUpdateEnabled, throwFrameRate: value,
             language: language, mascotStyle: mascotStyle, resourceSaving: resourceSaving)
    }

    public func withLanguage(_ value: AppLanguage) -> Self {
        Self(popupShortcut: popupShortcut, autoUpdateEnabled: autoUpdateEnabled, throwFrameRate: throwFrameRate,
             language: value, mascotStyle: mascotStyle, resourceSaving: resourceSaving)
    }

    public func withMascotStyle(_ value: MascotStyle) -> Self {
        Self(popupShortcut: popupShortcut, autoUpdateEnabled: autoUpdateEnabled, throwFrameRate: throwFrameRate,
             language: language, mascotStyle: value, resourceSaving: resourceSaving)
    }

    public func withResourceSaving(_ value: ResourceSaving) -> Self {
        Self(popupShortcut: popupShortcut, autoUpdateEnabled: autoUpdateEnabled, throwFrameRate: throwFrameRate,
             language: language, mascotStyle: mascotStyle, resourceSaving: value)
    }

    private enum CodingKeys: String, CodingKey {
        case popupShortcut
        case autoUpdateEnabled
        case throwFrameRate
        case language
        case mascotScale
        case mascotCount
        case mascotHue
        case resourceSaving
    }
}
