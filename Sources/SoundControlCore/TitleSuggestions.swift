import Foundation

/// Suggestions for the screen saver title: the owner's earlier titles first, then ones built from the system
/// (the user's name, the Mac's name), filtered by what is typed so far.
public enum TitleSuggestions {
    public static let limit = 6

    /// Titles built from system names, such as "Pond's Mac" or "Pond's screen".
    public static func systemTitles(fullName: String, computerName: String) -> [String] {
        let firstName = fullName.split(separator: " ").first.map(String.init) ?? ""
        var titles = [ScreenSaverSettings.defaultTitle]
        if !computerName.isEmpty { titles.append(computerName) }
        if !firstName.isEmpty {
            titles += ["\(firstName)'s screen", "Away — back soon", "\(firstName) is away"]
        } else {
            titles.append("Away — back soon")
        }
        return titles
    }

    /// Matches by prefix first, then anywhere, ignoring case; drops duplicates and the exact text typed.
    public static func suggestions(for query: String, recent: [String], system: [String]) -> [String] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let pool = (recent + system).filter { seen.insert($0.lowercased()).inserted }
        guard !typed.isEmpty else { return Array(pool.prefix(limit)) }
        let candidates = pool.filter { $0.caseInsensitiveCompare(typed) != .orderedSame }
        let prefix = candidates.filter { $0.lowercased().hasPrefix(typed.lowercased()) }
        let inside = candidates.filter { !prefix.contains($0) && $0.localizedCaseInsensitiveContains(typed) }
        return Array((prefix + inside).prefix(limit))
    }
}
