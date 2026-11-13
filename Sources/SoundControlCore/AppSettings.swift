import Foundation

/// Settings for the whole app, not one module. Stored as JSON next to `config.json`.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let `default` = AppSettings(popupShortcut: nil, autoUpdateEnabled: true)

    /// Global shortcut that opens the menu-bar popup on the Control tab, nil when none is set.
    public let popupShortcut: KeyShortcut?

    /// Automatically check GitHub Releases and install updates in the background.
    public let autoUpdateEnabled: Bool

    public init(popupShortcut: KeyShortcut?, autoUpdateEnabled: Bool = true) {
        self.popupShortcut = popupShortcut
        self.autoUpdateEnabled = autoUpdateEnabled
    }

    /// An unusable shortcut is dropped instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shortcut = try? container.decodeIfPresent(KeyShortcut.self, forKey: .popupShortcut)
        let autoUpdate = (try? container.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled)) ?? true
        self.init(popupShortcut: shortcut, autoUpdateEnabled: autoUpdate)
    }

    public func withPopupShortcut(_ value: KeyShortcut?) -> Self {
        Self(popupShortcut: value, autoUpdateEnabled: autoUpdateEnabled)
    }

    public func withAutoUpdate(_ value: Bool) -> Self {
        guard value != autoUpdateEnabled else { return self }
        return Self(popupShortcut: popupShortcut, autoUpdateEnabled: value)
    }

    private enum CodingKeys: String, CodingKey {
        case popupShortcut
        case autoUpdateEnabled
    }
}
