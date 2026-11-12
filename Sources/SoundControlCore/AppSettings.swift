import Foundation

/// Settings for the whole app, not one module. Stored as JSON next to `config.json`.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let `default` = AppSettings(popupShortcut: nil)

    /// Global shortcut that opens the menu-bar popup on the Control tab, nil when none is set.
    public let popupShortcut: KeyShortcut?

    public init(popupShortcut: KeyShortcut?) {
        self.popupShortcut = popupShortcut
    }

    /// An unusable shortcut is dropped instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(popupShortcut: try? container.decodeIfPresent(KeyShortcut.self, forKey: .popupShortcut))
    }

    public func withPopupShortcut(_ value: KeyShortcut?) -> Self {
        Self(popupShortcut: value)
    }

    private enum CodingKeys: String, CodingKey {
        case popupShortcut
    }
}
