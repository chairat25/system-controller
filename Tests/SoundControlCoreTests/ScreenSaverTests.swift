import Foundation
import Testing
@testable import SoundControlCore

@Suite("Screen saver settings")
struct ScreenSaverSettingsTests {
    private let dimming = ScreenSaverSettings(widgets: [.clock], isDimEnabled: true,
                                              dimAfterSeconds: 60, dimLevel: 0.2, fadeSeconds: 100)

    @Test("full brightness until the dim delay passes")
    func brightBeforeDelay() {
        #expect(dimming.brightness(idle: 0) == 1)
        #expect(dimming.brightness(idle: 60) == 1)
    }

    @Test("fades in a straight line down to the dim level")
    func fades() {
        #expect(abs(dimming.brightness(idle: 110) - 0.6) < 1e-9)
        #expect(abs(dimming.brightness(idle: 160) - 0.2) < 1e-9)
        #expect(abs(dimming.brightness(idle: 9_999) - 0.2) < 1e-9)
    }

    @Test("a zero fade jumps straight to the dim level")
    func instant() {
        let instant = dimming.withFade(seconds: 0)
        #expect(instant.brightness(idle: 61) == 0.2)
    }

    @Test("dimming to zero reaches no light")
    func fullyDark() {
        let dark = dimming.withDimLevel(0)
        #expect(dark.brightness(idle: 10_000) == 0)
    }

    @Test("disabled dimming stays at full brightness")
    func disabled() {
        #expect(dimming.withDimEnabled(false).brightness(idle: 10_000) == 1)
    }

    @Test("values are clamped")
    func clamping() {
        let wild = ScreenSaverSettings(widgets: [], isDimEnabled: true, dimAfterSeconds: -5,
                                       dimLevel: 7, fadeSeconds: 999_999)
        #expect(wild.dimAfterSeconds == ScreenSaverSettings.minimumDimAfter)
        #expect(wild.dimLevel == 1)
        #expect(wild.fadeSeconds == ScreenSaverSettings.maximumFade)
        #expect(ScreenSaverSettings.default.withDimLevel(.nan).dimLevel == 0)
    }

    @Test("widgets keep a fixed order and never repeat")
    func widgetOrder() {
        let settings = ScreenSaverSettings(widgets: [.claudeUsage, .clock, .clock], isDimEnabled: false,
                                           dimAfterSeconds: 60, dimLevel: 0, fadeSeconds: 0)
        #expect(settings.widgets == [.clock, .claudeUsage])
        let toggled = settings.showing(.calendar, true).showing(.clock, false)
        #expect(toggled.widgets == [.calendar, .claudeUsage])
        #expect(toggled.shows(.calendar) && !toggled.shows(.clock))
    }

    @Test("round-trips through JSON and tolerates missing fields")
    func codable() throws {
        let data = try JSONEncoder().encode(dimming)
        #expect(try JSONDecoder().decode(ScreenSaverSettings.self, from: data) == dimming)
        #expect(try JSONDecoder().decode(ScreenSaverSettings.self, from: Data("{}".utf8)) == .default)
    }
}

@Suite("Claude usage")
struct ClaudeUsageTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 11) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ id: String, _ date: Date, tokens: Int = 100) -> TokenUsageEntry {
        TokenUsageEntry(id: id, date: date, tokens: tokens)
    }

    @Test("parses an assistant line and skips cache reads")
    func parsesLine() throws {
        let line = #"""
        {"type":"assistant","timestamp":"2026-11-11T05:26:34.798Z","message":{"id":"msg_1","usage":{"input_tokens":2,"cache_creation_input_tokens":40,"cache_read_input_tokens":9999,"output_tokens":8}}}
        """#
        let parsed = try #require(ClaudeUsage.entry(fromLine: Data(line.utf8)))
        #expect(parsed.id == "msg_1")
        #expect(parsed.tokens == 50)
    }

    @Test("accepts timestamps without fractional seconds")
    func plainTimestamp() {
        let line = #"{"type":"assistant","timestamp":"2026-11-11T05:26:34Z","message":{"id":"a","usage":{"output_tokens":1}}}"#
        #expect(ClaudeUsage.entry(fromLine: Data(line.utf8)) != nil)
    }

    @Test("ignores user lines, missing usage and garbage")
    func skips() {
        let lines = [
            #"{"type":"user","timestamp":"2026-11-11T05:26:34Z","message":{"id":"a","usage":{"output_tokens":1}}}"#,
            #"{"type":"assistant","timestamp":"2026-11-11T05:26:34Z","message":{"id":"a"}}"#,
            #"{"type":"assistant","timestamp":"nope","message":{"id":"a","usage":{"output_tokens":1}}}"#,
            "not json"
        ]
        for line in lines { #expect(ClaudeUsage.entry(fromLine: Data(line.utf8)) == nil) }
    }

    @Test("sums today and the open five-hour window")
    func window() {
        let entries = [entry("old", date(1, day: 10)), entry("a", date(8, 20)), entry("b", date(10, 5), tokens: 300)]
        let summary = ClaudeUsage.summary(of: entries, now: date(11), calendar: Self.utc)
        #expect(summary.todayTokens == 400)
        #expect(summary.todayReplies == 2)
        #expect(summary.windowTokens == 400)
        #expect(summary.windowResetsAt == date(13))
    }

    @Test("a reply after the window ended opens a new window")
    func newWindow() {
        let entries = [entry("a", date(1)), entry("b", date(7, 30), tokens: 50)]
        let summary = ClaudeUsage.summary(of: entries, now: date(8), calendar: Self.utc)
        #expect(summary.windowTokens == 50)
        #expect(summary.windowResetsAt == date(12))
        #expect(summary.todayTokens == 150)
    }

    @Test("no window is open once five hours have passed")
    func expired() {
        let summary = ClaudeUsage.summary(of: [entry("a", date(1))], now: date(9), calendar: Self.utc)
        #expect(summary.windowTokens == 0)
        #expect(summary.windowResetsAt == nil)
        #expect(summary.todayTokens == 100)
    }

    @Test("formats token counts compactly")
    func format() {
        #expect(ClaudeUsageSummary.format(tokens: 950) == "950")
        #expect(ClaudeUsageSummary.format(tokens: 12_345) == "12.3K")
        #expect(ClaudeUsageSummary.format(tokens: 4_600_000) == "4.6M")
    }
}

@Suite("Key shortcut")
struct KeyShortcutTests {
    @Test("needs a real key and one of command, option or control")
    func validity() {
        #expect(KeyShortcut(keyCode: 37, modifiers: [.control, .option], label: "L") != nil)
        #expect(KeyShortcut(keyCode: 37, modifiers: [], label: "L") == nil)
        #expect(KeyShortcut(keyCode: 37, modifiers: [.shift], label: "L") == nil)
        #expect(KeyShortcut(keyCode: 37, modifiers: [.command], label: "") == nil)
        #expect(KeyShortcut(keyCode: -1, modifiers: [.command], label: "L") == nil)
    }

    @Test("shows modifiers in macOS order before the key")
    func display() throws {
        let shortcut = try #require(KeyShortcut(keyCode: 37, modifiers: [.command, .shift, .control, .option], label: "L"))
        #expect(shortcut.displayString == "⌃⌥⇧⌘L")
    }

    @Test("names special keys and upper-cases letters")
    func labels() {
        #expect(KeyShortcut.label(forKeyCode: 49, characters: " ") == "Space")
        #expect(KeyShortcut.label(forKeyCode: 96, characters: nil) == "F5")
        #expect(KeyShortcut.label(forKeyCode: 37, characters: "l") == "L")
        #expect(KeyShortcut.label(forKeyCode: 200, characters: nil) == "")
    }

    @Test("is saved with the screen saver settings")
    func roundTrip() throws {
        let shortcut = try #require(KeyShortcut(keyCode: 37, modifiers: [.control, .option], label: "L"))
        let settings = ScreenSaverSettings.default.withShortcut(shortcut)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ScreenSaverSettings.self, from: data).shortcut == shortcut)
        #expect(settings.withFade(seconds: 5).shortcut == shortcut)
        #expect(settings.withShortcut(nil).shortcut == nil)
    }

    @Test("an unusable saved shortcut is dropped, not fatal")
    func badShortcut() throws {
        let json = #"{"fadeSeconds":7,"shortcut":{"keyCode":37,"modifiers":0,"label":"L"}}"#
        let settings = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(json.utf8))
        #expect(settings.shortcut == nil)
        #expect(settings.fadeSeconds == 7)
    }
}

@Suite("Bright clock and pinned sessions")
struct ClockAndPinTests {
    private let base = ScreenSaverSettings.default

    @Test("the clock follows the screen when bright clock is off")
    func clockFollowsScreen() {
        #expect(base.clockBrightness(screen: 0.3) == 0.3)
    }

    @Test("a bright clock fades with the screen, then holds at its own level")
    func clockHolds() {
        let bright = base.withClockBright(true).withClockLevel(0.6)
        #expect(bright.clockBrightness(screen: 1) == 1)
        #expect(bright.clockBrightness(screen: 0.8) == 0.8)
        #expect(bright.clockBrightness(screen: 0.2) == 0.6)
        #expect(bright.clockBrightness(screen: 0) == 0.6)
    }

    @Test("clock level is clamped and survives the other changes")
    func clockLevelKept() {
        #expect(base.withClockLevel(7).clockLevel == 1)
        #expect(base.withClockLevel(-1).clockLevel == 0)
        let next = base.withClockBright(true).withClockLevel(0.4).withDimLevel(0.1).withFade(seconds: 5)
        #expect(next.isClockBright)
        #expect(next.clockLevel == 0.4)
    }

    @Test("pins keep order, never repeat and are capped")
    func pins() {
        let pinned = base.pinning("a", true).pinning("b", true).pinning("a", true)
        #expect(pinned.pinnedSessionIDs == ["b", "a"])
        #expect(pinned.isPinned("a"))
        #expect(!pinned.pinning("a", false).isPinned("a"))
        let many = (0..<30).reduce(base) { $0.pinning("s\($1)", true) }
        #expect(many.pinnedSessionIDs.count == ScreenSaverSettings.maximumPins)
        #expect(many.pinnedSessionIDs.last == "s29")
    }

    @Test("new fields round-trip, and an old file gets the defaults")
    func roundTrip() throws {
        let custom = base.withShowsSessions(false).withClockBright(true).withClockLevel(0.5).pinning("x", true)
        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
        let old = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"fadeSeconds":5}"#.utf8))
        #expect(old.showsSessions)
        #expect(!old.isClockBright)
        #expect(old.clockLevel == 1)
        #expect(old.pinnedSessionIDs.isEmpty)
    }

    @Test("clearing the shortcut keeps the rest")
    func shortcutCleared() {
        let key = KeyShortcut(keyCode: 37, modifiers: [.control, .option], label: "L")
        let set = base.withShortcut(key).withClockBright(true)
        #expect(set.shortcut == key)
        let cleared = set.withShortcut(nil)
        #expect(cleared.shortcut == nil)
        #expect(cleared.isClockBright)
    }
}

@Suite("Sessions corner")
struct SessionsCornerTests {
    @Test("starts top-left and can move to any corner without touching the rest")
    func moves() {
        let base = ScreenSaverSettings.default
        #expect(base.sessionsCorner == .topLeft)
        for corner in ScreenSaverCorner.allCases {
            let moved = base.withClockBright(true).pinning("a", true).withSessionsCorner(corner)
            #expect(moved.sessionsCorner == corner)
            #expect(moved.isClockBright)
            #expect(moved.isPinned("a"))
        }
    }

    @Test("round-trips, and an old or unknown value gives the default")
    func persists() throws {
        let moved = ScreenSaverSettings.default.withSessionsCorner(.bottomRight)
        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(moved))
        #expect(decoded.sessionsCorner == .bottomRight)
        let old = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"fadeSeconds":5}"#.utf8))
        #expect(old.sessionsCorner == .topLeft)
        let odd = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"sessionsCorner":"middle"}"#.utf8))
        #expect(odd.sessionsCorner == .topLeft)
    }

    @Test("knows which side and edge each corner is on")
    func geometry() {
        #expect(ScreenSaverCorner.topLeft.isTop && ScreenSaverCorner.topLeft.isLeft)
        #expect(!ScreenSaverCorner.bottomRight.isTop && !ScreenSaverCorner.bottomRight.isLeft)
        #expect(ScreenSaverCorner.bottomLeft.isLeft && !ScreenSaverCorner.bottomLeft.isTop)
    }
}

@Suite("Screen saver background")
struct ScreenSaverBackgroundTests {
    @Test("defaults to pitch black, presets exclude custom photo, and every case has a title")
    func defaultsAndPresets() {
        #expect(ScreenSaverSettings.default.background == .pitchBlack)
        #expect(ScreenSaverSettings.default.customBackgroundName == nil)
        #expect(!ScreenSaverBackground.presets.contains(.customImage))
        #expect(ScreenSaverBackground.presets.contains(.desktopWallpaper))
        for background in ScreenSaverBackground.allCases {
            #expect(!background.title.isEmpty)
        }
    }

    @Test("changes background and custom photo cleanly without touching other settings")
    func updates() {
        let base = ScreenSaverSettings.default.withClockBright(true).withMascot(.penguin)
        let aurora = base.withBackground(.aurora)
        #expect(aurora.background == .aurora)
        #expect(aurora.isClockBright && aurora.mascot == .penguin)

        let custom = aurora.withCustomBackground(name: "  My Wallpaper  ")
        #expect(custom.background == .customImage)
        #expect(custom.customBackgroundName == "My Wallpaper")

        let switched = custom.withBackground(.ocean)
        #expect(switched.background == .ocean)
        #expect(switched.customBackgroundName == "My Wallpaper")

        let backToCustom = switched.withBackground(.customImage)
        let clearedFromCustom = backToCustom.withCustomBackground(name: nil)
        #expect(clearedFromCustom.background == .pitchBlack)
        #expect(clearedFromCustom.customBackgroundName == nil)

        let clearedFromPreset = switched.withCustomBackground(name: "   ")
        #expect(clearedFromPreset.background == .ocean)
        #expect(clearedFromPreset.customBackgroundName == nil)
    }

    @Test("round-trips through JSON and falls back to pitch black on legacy or unknown values")
    func persists() throws {
        let custom = ScreenSaverSettings.default
            .withCustomBackground(name: "Night Sky")
            .withBackground(.cosmos)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: data)
        #expect(decoded.background == .cosmos)
        #expect(decoded.customBackgroundName == "Night Sky")

        let legacy = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"fadeSeconds":15}"#.utf8))
        #expect(legacy.background == .pitchBlack)
        #expect(legacy.customBackgroundName == nil)

        let unknown = try JSONDecoder().decode(
            ScreenSaverSettings.self,
            from: Data(#"{"background":"hologram","customBackgroundName":"  "}"#.utf8)
        )
        #expect(unknown.background == .pitchBlack)
        #expect(unknown.customBackgroundName == nil)
    }
}

@Suite("Draggable widgets and stacking order")
struct WidgetDragLayoutTests {
    @Test("starts with default layout and promotes the most recently moved widget to the top layer repeatedly")
    func promotesToTopRepeatedly() {
        let base = ScreenSaverSettings.default
        #expect(!base.hasCustomWidgetLayout)
        #expect(base.widgetOrder == ScreenSaverItem.allCases)

        let first = base.moving(.clock, to: WidgetPosition(x: 0.2, y: 0.3))
        #expect(first.hasCustomWidgetLayout)
        #expect(first.widgetOrder.last == .clock)
        #expect(first.position(for: .clock) == WidgetPosition(x: 0.2, y: 0.3))

        let second = first.moving(.calendar, to: WidgetPosition(x: 0.25, y: 0.35))
        #expect(second.widgetOrder.last == .calendar)
        #expect(second.zIndex(of: .calendar) > second.zIndex(of: .clock))

        let third = second.moving(.sessions, to: WidgetPosition(x: 0.22, y: 0.32))
        #expect(third.widgetOrder.last == .sessions)
        #expect(third.zIndex(of: .sessions) > third.zIndex(of: .calendar))

        let reStacked = third.moving(.clock, to: WidgetPosition(x: 0.24, y: 0.34))
        #expect(reStacked.widgetOrder.last == .clock)
        #expect(reStacked.zIndex(of: .clock) > reStacked.zIndex(of: .sessions))
        #expect(reStacked.zIndex(of: .sessions) > reStacked.zIndex(of: .calendar))
    }

    @Test("clamps normalized coordinates, resets cleanly, and clears sessions override when corner preset is picked")
    func clampsAndResets() {
        let moved = ScreenSaverSettings.default
            .withClockBright(true)
            .moving(.calendar, to: WidgetPosition(x: -0.5, y: 1.8))
            .moving(.sessions, to: WidgetPosition(x: 0.4, y: 0.5))

        #expect(moved.position(for: .calendar) == WidgetPosition(x: 0, y: 1))

        let cornerPicked = moved.withSessionsCorner(.bottomLeft)
        #expect(cornerPicked.sessionsCorner == .bottomLeft)
        #expect(cornerPicked.position(for: .sessions) == nil)
        #expect(cornerPicked.position(for: .calendar) == WidgetPosition(x: 0, y: 1))

        let reset = cornerPicked.resetWidgetLayout()
        #expect(!reset.hasCustomWidgetLayout)
        #expect(reset.widgetPositions.isEmpty)
        #expect(reset.widgetOrder == ScreenSaverItem.allCases)
        #expect(reset.isClockBright)
    }

    @Test("persists custom positions and order, while legacy JSON falls back to defaults")
    func persistence() throws {
        let custom = ScreenSaverSettings.default
            .moving(.claudeUsage, to: WidgetPosition(x: 0.75, y: 0.25))
            .bringingToFront(.clock)

        let decoded = try JSONDecoder().decode(ScreenSaverSettings.self, from: JSONEncoder().encode(custom))
        #expect(decoded.widgetPositions == custom.widgetPositions)
        #expect(decoded.widgetOrder == custom.widgetOrder)

        let legacy = try JSONDecoder().decode(ScreenSaverSettings.self, from: Data(#"{"fadeSeconds":12}"#.utf8))
        #expect(!legacy.hasCustomWidgetLayout)
        #expect(legacy.widgetOrder == ScreenSaverItem.allCases)
    }

    @Test("canvas geometry keeps widgets in bounds, round-trips across display sizes, and detects overlap layers")
    func geometryAndOverlaps() {
        let canvas = CanvasSize(width: 1440, height: 900)
        let cardSize = CanvasSize(width: 280, height: 220)

        let clamped = WidgetCanvasLayout.clampedCenter(CanvasPoint(x: 10, y: 950), itemSize: cardSize, canvasSize: canvas)
        let bounds = WidgetCanvasLayout.centerBounds(itemSize: cardSize, canvasSize: canvas)
        #expect(abs(clamped.x - bounds.minX) < 0.001)
        #expect(abs(clamped.y - bounds.maxY) < 0.001)

        let target = CanvasPoint(x: 620, y: 410)
        let normalized = WidgetCanvasLayout.normalizedPosition(fromCenter: target, itemSize: cardSize, canvasSize: canvas)
        let restored = WidgetCanvasLayout.pixelCenter(from: normalized, itemSize: cardSize, canvasSize: canvas)
        #expect(abs(restored.x - target.x) < 0.01)
        #expect(abs(restored.y - target.y) < 0.01)

        let order: [ScreenSaverItem] = [.calendar, .claudeUsage, .clock]
        let rects: [ScreenSaverItem: CanvasRect] = [
            .calendar: CanvasRect(center: CanvasPoint(x: 500, y: 400), size: CanvasSize(width: 280, height: 270)),
            .claudeUsage: CanvasRect(center: CanvasPoint(x: 560, y: 420), size: CanvasSize(width: 270, height: 200)),
            .clock: CanvasRect(center: CanvasPoint(x: 600, y: 440), size: CanvasSize(width: 320, height: 170)),
        ]
        let states = WidgetCanvasLayout.overlapStates(order: order, rects: rects)
        #expect(states[.calendar]?.overlapsLower == false)
        #expect(states[.calendar]?.isCoveredByUpper == true)
        #expect(states[.claudeUsage]?.overlapsLower == true)
        #expect(states[.claudeUsage]?.isCoveredByUpper == true)
        #expect(states[.clock]?.overlapsLower == true)
        #expect(states[.clock]?.isCoveredByUpper == false)
    }
}
