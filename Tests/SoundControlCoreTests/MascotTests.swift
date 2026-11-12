import Foundation
import Testing
@testable import SoundControlCore

@Suite("Mascot route")
struct MascotRouteTests {
    private let route = MascotRoute(seed: 42, width: 1200)

    @Test("starts resting in the middle")
    func startsInMiddle() {
        let (pose, _) = route.pose(at: 0)
        #expect(pose.x == 600)
        #expect(!pose.isWalking)
    }

    @Test("always stays on the walk, for hours")
    func staysInside() {
        var cursor = MascotRoute.Cursor.origin
        for second in stride(from: 0.0, through: 4 * 3600, by: 7.3) {
            let (pose, next) = route.pose(at: second, from: cursor)
            cursor = next
            #expect((0...1200).contains(pose.x))
        }
    }

    @Test("the saved cursor gives the same pose as starting over")
    func cursorMatchesOrigin() {
        var cursor = MascotRoute.Cursor.origin
        for second in stride(from: 0.0, through: 600, by: 0.9) {
            let (cached, next) = route.pose(at: second, from: cursor)
            cursor = next
            #expect(cached == route.pose(at: second).0)
        }
    }

    @Test("a clock that goes back restarts the route instead of breaking")
    func clockGoesBack() {
        let (_, late) = route.pose(at: 900)
        #expect(route.pose(at: 5, from: late).0 == route.pose(at: 5).0)
    }

    @Test("walks between stops, faces where it goes and counts steps")
    func walks() throws {
        let walking: MascotPose? = stride(from: 0.0, through: 300, by: 0.25).lazy.map { route.pose(at: $0).0 }.first { $0.isWalking }
        let pose = try #require(walking)
        #expect(pose.steps >= 0)
        let (later, _) = route.pose(at: route.pause(0) + 1)
        #expect(later.isWalking == (route.stop(1) != route.stop(0)))
        #expect(later.facesRight == (route.stop(1) > route.stop(0)))
    }

    @Test("pauses last between two and seven seconds")
    func pauses() {
        for leg in 0..<200 {
            #expect((2...7).contains(route.pause(leg)))
        }
    }

    @Test("no room to walk keeps it standing still")
    func noRoom() {
        let still = MascotRoute(seed: 1, width: 0)
        #expect(still.pose(at: 50).0.x == 0)
        #expect(!still.pose(at: 50).0.isWalking)
    }
}

@Suite("Mascot choice")
struct MascotChoiceTests {
    @Test("five animals, a cat by default, and None turns it off")
    func choices() {
        #expect(Mascot.animals.count == 5)
        #expect(!Mascot.animals.contains(.none))
        #expect(ScreenSaverSettings.default.mascot == .cat)
        #expect(ScreenSaverSettings.default.withMascot(.none).mascot == .none)
    }

    @Test("round-trips, keeps other settings, and an unknown animal gives the default")
    func persists() throws {
        let chosen = ScreenSaverSettings.default.withClockBright(true).withMascot(.penguin)
        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(chosen))
        #expect(decoded.mascot == .penguin)
        #expect(decoded.isClockBright)
        let odd = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"mascot":"dragon"}"#.utf8))
        #expect(odd.mascot == .cat)
    }
}

@Suite("App settings")
struct AppSettingsTests {
    @Test("no popup shortcut until one is set, and it round-trips")
    func popupShortcut() throws {
        #expect(AppSettings.default.popupShortcut == nil)
        let shortcut = try #require(KeyShortcut(keyCode: 49, modifiers: [.option], label: "Space"))
        let set = AppSettings.default.withPopupShortcut(shortcut)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(set))
        #expect(decoded.popupShortcut == shortcut)
        #expect(decoded.withPopupShortcut(nil).popupShortcut == nil)
    }

    @Test("a broken or empty file gives the defaults")
    func lenient() throws {
        let broken = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"popupShortcut":"oops"}"#.utf8))
        #expect(broken.popupShortcut == nil)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == .default)
    }
}

@Suite("Mascot stays lit")
struct MascotLitTests {
    @Test("follows the screen until kept lit, then holds its own level")
    func brightness() {
        let base = ScreenSaverSettings.default
        #expect(!base.isMascotBright)
        #expect(base.mascotBrightness(screen: 0.1) == 0.1)
        let lit = base.withMascotBright(true).withMascotLevel(0.4)
        #expect(lit.mascotBrightness(screen: 0) == 0.4)
        #expect(lit.mascotBrightness(screen: 0.9) == 0.9)
        #expect(lit.clockBrightness(screen: 0) == 0, "the clock is set on its own")
    }

    @Test("round-trips, clamps the level, and old files keep it off")
    func persists() throws {
        let lit = ScreenSaverSettings.default.withMascotBright(true).withMascotLevel(7)
        #expect(lit.mascotLevel == 1)
        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(lit.withMascotLevel(0.3)))
        #expect(decoded.isMascotBright && decoded.mascotLevel == 0.3)
        let old = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"isClockBright":true}"#.utf8))
        #expect(!old.isMascotBright && old.mascotLevel == 1)
    }
}
