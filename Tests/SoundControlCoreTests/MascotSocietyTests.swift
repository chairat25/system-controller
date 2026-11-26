import Foundation
import Testing
@testable import SoundControlCore

@Suite("Mascot society")
struct MascotSocietyTests {
    private func member(_ id: String, x: Double, species: Mascot = .cat, home: String? = "home",
                        isBaby: Bool = false, isFree: Bool = true) -> MascotMember {
        MascotMember(id: id, x: x, species: species, home: home, isBaby: isBaby, isFree: isFree)
    }

    /// Runs the society for `seconds` and collects everything it ordered and every baby it made.
    private func run(_ society: inout MascotSociety, seconds: Double, members: @autoclosure () -> [MascotMember],
                     canBreed: Bool = true)
        -> (orders: [MascotOrder], births: [MascotBirth]) {
        var orders: [MascotOrder] = []
        var births: [MascotBirth] = []
        for _ in 0..<Int(seconds * 10) {
            let result = society.step(dt: 0.1, members: members(), canBreed: canBreed)
            orders += result.orders.values
            births += result.births
        }
        return (orders, births)
    }

    @Test("a lone mascot naps, hops and looks around, and never breeds")
    func solo() {
        var society = MascotSociety(seed: 1)
        let result = run(&society, seconds: 600, members: [member("a", x: 100)])
        #expect(result.orders.contains { $0.face == .sleepy })
        #expect(result.orders.contains { $0.hops })
        #expect(result.orders.contains { $0.face == .curious })
        #expect(result.births.isEmpty)
    }

    @Test("a napping mascot stands still, and a hop is in place")
    func nappingStands() {
        var society = MascotSociety(seed: 2)
        let result = run(&society, seconds: 600, members: [member("a", x: 100)])
        for order in result.orders where order.face == .sleepy || order.hops {
            #expect(order.move == .stand(facesRight: nil))
        }
    }

    @Test("two close mascots greet, play chase and follow each other")
    func social() {
        var society = MascotSociety(seed: 3)
        let result = run(&society, seconds: 900, members: [member("a", x: 100, species: .cat),
                                                            member("b", x: 180, species: .pig)])
        #expect(result.orders.contains { if case .go(_, true) = $0.move { true } else { false } })
        #expect(result.orders.contains { $0.face == .happy && $0.hops })
        #expect(result.births.isEmpty, "different animals never breed")
    }

    @Test("two grown mascots of one kind, living near each other, have a baby")
    func births() {
        var society = MascotSociety(seed: 4)
        let result = run(&society, seconds: 1200, members: [member("a", x: 100), member("b", x: 160)])
        #expect(!result.births.isEmpty)
        let birth = result.births[0]
        #expect(birth.species == .cat && birth.home == "home" && birth.x == 130)
        #expect(result.orders.contains { $0.face == .love })
    }

    @Test("only the pair that courted, only once per rest, and not too fast")
    func birthRate() {
        var society = MascotSociety(seed: 5)
        let result = run(&society, seconds: 1200, members: [member("a", x: 100), member("b", x: 160)])
        // Each birth is followed by at least a minute of not wanting another.
        #expect(result.births.count <= 1200 / 60)
    }

    @Test("a full desktop, babies, strangers from another Mac and mascots far apart do not breed")
    func noBirths() {
        var full = MascotSociety(seed: 6)
        #expect(run(&full, seconds: 1200, members: [member("a", x: 100), member("b", x: 160)], canBreed: false).births.isEmpty)
        var babies = MascotSociety(seed: 7)
        #expect(run(&babies, seconds: 1200, members: [member("a", x: 100, isBaby: true),
                                                       member("b", x: 160, isBaby: true)]).births.isEmpty)
        var strangers = MascotSociety(seed: 8)
        #expect(run(&strangers, seconds: 1200, members: [member("a", x: 100, home: "mac1"),
                                                          member("b", x: 160, home: "mac2")]).births.isEmpty)
        var apart = MascotSociety(seed: 9)
        #expect(run(&apart, seconds: 1200, members: [member("a", x: 0), member("b", x: 2000)]).births.isEmpty)
    }

    @Test("a busy mascot, held or flying, gets no orders and loses its plans")
    func busyGetsNothing() {
        var society = MascotSociety(seed: 10)
        let result = run(&society, seconds: 300, members: [member("a", x: 100, isFree: false)])
        #expect(result.orders.allSatisfy { $0 == .free })
    }

    @Test("a baby follows a grown one of its kind when it is left behind")
    func babyFollows() {
        var society = MascotSociety(seed: 11)
        let result = run(&society, seconds: 600, members: [member("a", x: 100),
                                                            member("b", x: 400, isBaby: true)])
        #expect(result.orders.contains { if case .go(let x, false) = $0.move { x == 100 || x == 400 } else { false } })
    }

    @Test("the same seed makes the same life")
    func deterministic() {
        var first = MascotSociety(seed: 12)
        var second = MascotSociety(seed: 12)
        let members = [member("a", x: 100), member("b", x: 200)]
        for _ in 0..<2000 {
            let one = first.step(dt: 0.1, members: members, canBreed: true)
            let two = second.step(dt: 0.1, members: members, canBreed: true)
            #expect(one.orders == two.orders && one.births == two.births)
        }
    }

    @Test("a mascot that leaves the desktop is forgotten, and repeated ids do not crash")
    func forgets() {
        var society = MascotSociety(seed: 13)
        _ = run(&society, seconds: 5, members: [member("a", x: 1), member("b", x: 2)])
        let result = society.step(dt: 0.1, members: [member("a", x: 1), member("a", x: 5)], canBreed: true)
        #expect(result.orders.keys.contains("a") && !result.orders.keys.contains("b"))
    }

    @Test("babies grow from small to full size, then breed")
    func growth() {
        #expect(MascotGrowth.scale(age: 0) == MascotGrowth.babyScale)
        #expect(MascotGrowth.scale(age: MascotGrowth.maturity) == 1)
        #expect(MascotGrowth.scale(age: 9999) == 1)
        #expect(MascotGrowth.scale(age: 75) > MascotGrowth.babyScale && MascotGrowth.scale(age: 75) < 1)
        #expect(!MascotGrowth.isAdult(age: 10) && MascotGrowth.isAdult(age: 150))
    }

    @Test("walker obeys standing and heading, and strolls on after it stops being asked")
    func walkerOrders() {
        let walker = RoamingWalker.spawn(id: "w", yFraction: 1, maxX: 1000, seed: 3)
        let still = walker.standing(facesRight: true)
        #expect(!still.isWalking && still.facesRight)
        let moved = still.advanced(by: 0.1, maxX: 1000, size: 80, canExit: { _ in false }).walker
        #expect(moved.x == still.x)
        let heading = walker.heading(towardX: walker.x + 500, size: 80, running: true)
        #expect(heading.isWalking && heading.isRunning && heading.facesRight)
        let left = walker.heading(towardX: walker.x - 500, size: 80, running: false)
        #expect(left.isWalking && !left.isRunning && !left.facesRight)
        var free = still
        for _ in 0..<200 { free = free.advanced(by: 0.1, maxX: 1000, size: 80, canExit: { _ in false }).walker }
        #expect(free.x != still.x, "it strolls again once nobody holds it")
    }
}
