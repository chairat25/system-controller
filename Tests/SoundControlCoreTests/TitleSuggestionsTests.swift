import Foundation
import Testing
@testable import SoundControlCore

@Suite("Screen saver title")
struct TitleSuggestionsTests {
    @Test("prefix matches come before inside matches, recent before system, no duplicates")
    func ranking() {
        let result = TitleSuggestions.suggestions(for: "po", recent: ["Pond away", "Spot"], system: ["pond away", "Podium"])
        #expect(result == ["Pond away", "Podium", "Spot"])
    }

    @Test("empty query lists everything up to the limit")
    func emptyQuery() {
        let many = (0..<10).map { "T\($0)" }
        #expect(TitleSuggestions.suggestions(for: " ", recent: many, system: []).count == TitleSuggestions.limit)
    }

    @Test("system titles use the first name and the Mac name")
    func systemTitles() {
        let titles = TitleSuggestions.systemTitles(fullName: "Pond Smith", computerName: "Pond's MacBook")
        #expect(titles.contains("Pond's screen"))
        #expect(titles.contains("Pond's MacBook"))
    }

    @Test("setting a title remembers it, blank falls back to the default")
    func history() {
        let s = ScreenSaverSettings.default.withTitle("  Lunch  ").withTitle("Meeting").withTitle("lunch")
        #expect(s.title == "lunch")
        #expect(s.recentTitles == ["lunch", "Meeting"])
        #expect(s.withTitle("   ").title == ScreenSaverSettings.defaultTitle)
    }

    @Test("widget scale is clamped and reset with the layout")
    func scale() {
        let s = ScreenSaverSettings.default.scaling(.calendar, to: 5)
        #expect(s.scale(of: .calendar) == 2)
        #expect(s.hasCustomWidgetLayout)
        #expect(s.resetWidgetLayout().scale(of: .calendar) == 1)
    }

    @Test("new fields survive a JSON round trip and old files decode")
    func coding() throws {
        let s = ScreenSaverSettings.default.withTitle("Hi").withShowsTitle(false).scaling(.clock, to: 1.5)
        let back = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let old = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data("{}".utf8))
        #expect(old.title == ScreenSaverSettings.defaultTitle && old.showsTitle)
    }
}
