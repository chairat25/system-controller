import Foundation
import Testing
@testable import SoundControlCore

@Suite("Window climbing")
struct WindowClimberTests {
    private let size = 64.0
    private let maxX = 1400.0
    /// A window standing on the floor, from x 600 to 1000, 500 points tall.
    private let window = ClimbSurface(id: 7, minX: 600, maxX: 1000, bottom: 0, top: 500)

    private func walker(x: Double, facesRight: Bool) -> RoamingWalker {
        var walker = RoamingWalker.landed(id: "m", x: x, facesRight: facesRight, seed: 1)
        // Rest until it starts walking, then turn it toward the window.
        for _ in 0..<400 where !walker.isWalking {
            walker = walker.advanced(by: 0.05, maxX: maxX, size: size) { _ in false }.walker
        }
        return walker.heading(towardX: facesRight ? maxX : 0, size: size, running: false)
    }

    @Test("a walker reaching the side of a window on the floor finds it to climb")
    func findsSide() {
        let rightward = walker(x: window.minX - size - 1, facesRight: true)
        #expect(WindowClimber.surface(ahead: rightward, in: [window], size: size)?.id == 7)
        let leftward = walker(x: window.maxX + 1, facesRight: false)
        #expect(WindowClimber.surface(ahead: leftward, in: [window], size: size)?.id == 7)
    }

    @Test("a window floating high above the floor, or one too short, is not climbed")
    func ignoresUnreachable() {
        let floating = ClimbSurface(id: 1, minX: 600, maxX: 1000, bottom: 300, top: 700)
        let short = ClimbSurface(id: 2, minX: 600, maxX: 1000, bottom: 0, top: 40)
        let near = walker(x: window.minX - size - 1, facesRight: true)
        #expect(WindowClimber.surface(ahead: near, in: [floating, short], size: size) == nil)
        let far = walker(x: 100, facesRight: true)
        #expect(WindowClimber.surface(ahead: far, in: [window], size: size) == nil)
    }

    @Test("in front of a window as wide as the screen, it climbs the near edge from the front")
    func climbsInnerEdge() {
        let wide = ClimbSurface(id: 3, minX: 32, maxX: maxX + 32, bottom: 0, top: 700)
        let atRight = walker(x: maxX - 40, facesRight: true)
        let found = WindowClimber.surface(ahead: atRight, in: [wide], size: size)
        #expect(found?.id == 3)
        let climber = WindowClimber.start(on: wide, facingRight: true, size: size, seed: 1, front: atRight.x + size)
        #expect(climber.x == wide.maxX - size / 2)
        let atLeft = walker(x: 30, facesRight: false)
        #expect(WindowClimber.surface(ahead: atLeft, in: [wide], size: size)?.id == 3)
        #expect(WindowClimber.start(on: wide, facingRight: false, size: size, seed: 1, front: atLeft.x).x
            == wide.minX - size / 2)
    }

    @Test("it climbs the side, steadily up, then walks on the top edge")
    func climbsToTop() throws {
        var climber = WindowClimber.start(on: window, facingRight: true, size: size, seed: 3)
        var lastLift = climber.lift
        var reachedTop = false
        for _ in 0..<(24 * 20) {
            guard case let .climbing(next) = climber.advanced(by: 1.0 / 24, surfaces: [window], size: size) else {
                Issue.record("left the window before reaching the top")
                return
            }
            #expect(next.lift >= lastLift - 0.001)
            lastLift = next.lift
            climber = next
            if climber.isOnTop { reachedTop = true; break }
        }
        #expect(reachedTop)
        #expect(climber.lift == window.top)
    }

    @Test("on top it stays over the window, and sooner or later jumps off beside it")
    func walksThenJumps() {
        var climber = WindowClimber.start(on: window, facingRight: true, size: size, seed: 9)
        for _ in 0..<(24 * 120) {
            switch climber.advanced(by: 1.0 / 24, surfaces: [window], size: size) {
            case let .climbing(next):
                if next.isOnTop {
                    #expect(next.x + size / 2 >= window.minX - 0.001)
                    #expect(next.x + size / 2 <= window.maxX + 0.001)
                }
                climber = next
            case let .jumped(fling):
                #expect(fling.lift > 0)
                #expect(fling.x + size / 2 < window.minX || fling.x + size / 2 > window.maxX)
                return
            }
        }
        Issue.record("never jumped off")
    }

    @Test("a window that closes drops it, and one that moves carries it along")
    func followsOrFalls() {
        var climber = WindowClimber.start(on: window, facingRight: true, size: size, seed: 2)
        for _ in 0..<(24 * 20) where !climber.isOnTop {
            if case let .climbing(next) = climber.advanced(by: 1.0 / 24, surfaces: [window], size: size) { climber = next }
        }
        #expect(climber.isOnTop)
        let moved = ClimbSurface(id: 7, minX: 700, maxX: 1100, bottom: 0, top: 420)
        guard case let .climbing(carried) = climber.advanced(by: 1.0 / 24, surfaces: [moved], size: size) else {
            Issue.record("fell off a window that only moved")
            return
        }
        #expect(carried.lift == 420)
        #expect(abs((carried.x - climber.x) - 100) < 10)
        guard case let .jumped(fall) = carried.advanced(by: 1.0 / 24, surfaces: [], size: size) else {
            Issue.record("kept standing on a closed window")
            return
        }
        #expect(fall.lift == 420)
    }
}
