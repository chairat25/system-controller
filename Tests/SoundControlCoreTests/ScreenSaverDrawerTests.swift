import Testing
@testable import SoundControlCore

@Suite("Two-finger swipe")
struct SwipeTrackerTests {
    @Test("a long sideways stroke is a swipe the way the fingers moved")
    func sideways() {
        let right = SwipeTracker.initial.adding(dx: 30, dy: 2).adding(dx: 40, dy: -3)
        #expect(right.direction == .right)
        let left = SwipeTracker.initial.adding(dx: -50, dy: 5).adding(dx: -30, dy: 0)
        #expect(left.direction == .left)
    }

    @Test("a short or mostly vertical stroke is not a swipe")
    func ignored() {
        #expect(SwipeTracker.initial.adding(dx: 20, dy: 0).direction == nil)
        #expect(SwipeTracker.initial.adding(dx: 90, dy: 120).direction == nil)
    }

    @Test("finger direction undoes natural scrolling")
    func natural() {
        #expect(SwipeTracker.fingerDelta(scrollDelta: 12, isNatural: true) == 12)
        #expect(SwipeTracker.fingerDelta(scrollDelta: 12, isNatural: false) == -12)
    }
}

@Suite("Screen saver drawers")
struct ScreenSaverDrawerTests {
    @Test("fingers right open the left drawer, fingers left open the right one")
    func opens() {
        #expect(ScreenSaverDrawer.closed.after(.right) == .dimming)
        #expect(ScreenSaverDrawer.closed.after(.left) == .widgets)
    }

    @Test("swiping back toward a drawer's edge closes it, the other way keeps it")
    func closes() {
        #expect(ScreenSaverDrawer.dimming.after(.left) == .closed)
        #expect(ScreenSaverDrawer.dimming.after(.right) == .dimming)
        #expect(ScreenSaverDrawer.widgets.after(.right) == .closed)
        #expect(ScreenSaverDrawer.widgets.after(.left) == .widgets)
    }
}

@Suite("Preset stepping")
struct PresetStepTests {
    @Test("steps through presets and stops at the ends")
    func steps() {
        let presets = [10, 30, 60]
        #expect(Presets.step(presets, from: 30, by: 1) == 60)
        #expect(Presets.step(presets, from: 60, by: 1) == 60)
        #expect(Presets.step(presets, from: 10, by: -1) == 10)
    }

    @Test("a custom value steps to the nearest preset on that side")
    func custom() {
        #expect(Presets.step([10, 30, 60], from: 45, by: 1) == 60)
        #expect(Presets.step([10, 30, 60], from: 45, by: -1) == 30)
    }
}

@Suite("Dimmed preview")
struct DimmedPreviewTests {
    @Test("endless idle gives the darkest level, or full light when dimming is off")
    func preview() {
        let settings = ScreenSaverSettings.default.withDimLevel(0.2)
        #expect(abs(settings.brightness(idle: .infinity) - 0.2) < 1e-9)
        #expect(settings.withDimEnabled(false).brightness(idle: .infinity) == 1)
    }
}
