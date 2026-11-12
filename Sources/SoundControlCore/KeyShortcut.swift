import Foundation

/// Modifier keys of a shortcut, independent of AppKit and Carbon.
public struct KeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)

    /// A global shortcut needs one of these, or it would fire while typing normal text.
    static let anchors: KeyModifiers = [.command, .option, .control]
}

/// A global keyboard shortcut the owner picks, such as ⌃⌥L.
public struct KeyShortcut: Codable, Sendable, Equatable {
    public let keyCode: Int
    public let modifiers: KeyModifiers
    /// What the key is called on screen, captured when recording: "L", "Space", "F5".
    public let label: String

    /// Nil unless the shortcut has a real key and at least one of ⌘ ⌥ ⌃.
    public init?(keyCode: Int, modifiers: KeyModifiers, label: String) {
        guard keyCode >= 0, !label.isEmpty, !modifiers.isDisjoint(with: .anchors) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(Int.self, forKey: .keyCode)
        let modifiers = try container.decode(KeyModifiers.self, forKey: .modifiers)
        let label = try container.decode(String.self, forKey: .label)
        guard let shortcut = Self(keyCode: keyCode, modifiers: modifiers, label: label) else {
            throw DecodingError.dataCorruptedError(forKey: .keyCode, in: container,
                                                   debugDescription: "Not a usable shortcut")
        }
        self = shortcut
    }

    /// macOS order: ⌃ ⌥ ⇧ ⌘, then the key.
    public var displayString: String {
        let symbols: [(KeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + label
    }

    /// Names for keys whose character is blank or unhelpful. Anything else shows its own letter.
    private static let specialLabels: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌅",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    /// The on-screen name of a key, from its virtual key code and the character it types.
    public static func label(forKeyCode keyCode: Int, characters: String?) -> String {
        if let special = specialLabels[keyCode] { return special }
        return (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, label
    }
}
