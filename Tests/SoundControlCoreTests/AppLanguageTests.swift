import Foundation
import Testing
@testable import SoundControlCore

@Suite("App language")
struct AppLanguageTests {
    @Test("English passes text through, Thai translates, unknown text stays English")
    func translates() {
        #expect(AppLanguage.english.translate("Hide mascot") == "Hide mascot")
        #expect(AppLanguage.thai.translate("Hide mascot") == "ซ่อนมาสคอต")
        #expect(AppLanguage.thai.translate("Not a known string") == "Not a known string")
    }

    @Test("fills %@ in order, in either language")
    func fills() {
        #expect(AppLanguage.english.translate("%@ of %@ on", ["3", "9"]) == "3 of 9 on")
        #expect(AppLanguage.thai.translate("%@ of %@ on", ["3", "9"]) == "เปิด 3 จาก 9")
        #expect(AppLanguage.english.translate("%@% left", ["40"]) == "40% left")
        #expect(AppLanguage.english.translate("Show %@", []) == "Show %@")
    }

    @Test("every Thai entry keeps the same number of %@ as its English key")
    func placeholdersMatch() {
        for (english, thai) in ThaiStrings.table {
            #expect(english.components(separatedBy: "%@").count == thai.components(separatedBy: "%@").count,
                    "\(english)")
            #expect(!thai.isEmpty)
        }
    }

    @Test("round-trips in app settings; old files stay in English")
    func persists() throws {
        let set = AppSettings.default.withLanguage(.thai)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(set))
        #expect(decoded.language == .thai)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.language == .english)
    }
}

@Suite("Mascot style")
struct MascotStyleTests {
    @Test("clamps size and count, wraps the colour shift, and survives bad numbers")
    func clamps() {
        let wild = MascotStyle(scale: 9, count: 99, hue: -30)
        #expect(wild.scale == 2 && wild.count == 6 && wild.hue == 330)
        let tiny = MascotStyle(scale: 0, count: 0, hue: 725)
        #expect(tiny.scale == 0.75 && tiny.count == 1 && tiny.hue == 5)
        #expect(MascotStyle(scale: .nan, count: 1, hue: .infinity) == .default)
        #expect(!MascotStyle.default.isRecoloured && MascotStyle(scale: 1, count: 1, hue: 40).isRecoloured)
    }

    @Test("round-trips in app settings; old files get the normal style")
    func persists() throws {
        let set = AppSettings.default.withMascotStyle(MascotStyle(scale: 1.5, count: 3, hue: 120))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(set))
        #expect(decoded.mascotStyle == MascotStyle(scale: 1.5, count: 3, hue: 120))
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoUpdateEnabled":true}"#.utf8))
        #expect(old.mascotStyle == .default)
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"mascotScale":"big","mascotCount":2}"#.utf8))
        #expect(odd.mascotStyle == MascotStyle(scale: 1, count: 2, hue: 0))
    }
}
