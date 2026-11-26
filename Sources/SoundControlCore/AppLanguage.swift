import Foundation

/// The language the app's own screens use. Kept on this Mac only (in `app.json`).
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case english = "en"
    case thai = "th"

    public static let `default` = AppLanguage.english

    public var id: String { rawValue }

    /// Each language names itself, so it can be found whatever is on screen.
    public var title: String {
        switch self {
        case .english: "English"
        case .thai: "ไทย"
        }
    }

    /// The text to show for an English UI string. Missing translations fall back to the English text.
    /// `%@` in the key is filled with `arguments`, in order, so phrases with numbers translate whole.
    public func translate(_ english: String, _ arguments: [String] = []) -> String {
        let template = self == .thai ? (ThaiStrings.table[english] ?? english) : english
        return Self.fill(template, arguments)
    }

    static func fill(_ template: String, _ arguments: [String]) -> String {
        guard !arguments.isEmpty else { return template }
        var result = ""
        var remaining = arguments[...]
        var rest = template[...]
        while let range = rest.range(of: "%@") {
            result += rest[..<range.lowerBound]
            result += remaining.popFirst() ?? ""
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}
