import AppKit
import SoundControlCore

/// Runs the desktop mascots on this Mac: keeps this Mac's own mascot alive, walks every mascot on screen, lets the
/// owner pick one up and throw it, makes it react to clicks (curious, then annoyed, then it runs away), points its
/// eyes at the mouse, and passes a mascot to a paired Mac when it walks or flies off an edge with a
/// neighbour. Visitors keep the look of their home Mac. Panels and timers exist only between `start` and `stop`.
@MainActor
final class DesktopMascotController {
    private static let frameInterval: TimeInterval = 1.0 / 24
    /// While every mascot rests, 12 frames a second still shows breathing and blinks, at half the work.
    private static let restingInterval: TimeInterval = 1.0 / 12
    private static let idleInterval: TimeInterval = 5
    private static let maximumTickGap: TimeInterval = 0.25
    /// This Mac's mascot handed to a Mac that vanished is lost; a new one appears after this long.
    private static let respawnDelay: TimeInterval = 60
    private static let maximumMascots = 4
    private static let bottom = 1.0
    /// Only the last moments of a drag decide the throw.
    private static let throwWindow: TimeInterval = 0.08

    private enum Motion {
        case walking(RoamingWalker)
        case held(x: Double, lift: Double, since: Date)
        case flying(MascotFling)
    }

    private struct Item {
        let id: String
        let home: String?
        let look: Mascot?
        var motion: Motion
        var mood = MascotMood.calm
        let panel: DesktopMascotPanel
        let sprite: DesktopMascotSprite

        var isHeld: Bool {
            if case .held = motion { return true }
            return false
        }

        /// Resting on the floor: nothing moves but breathing and blinks.
        var isResting: Bool {
            if case let .walking(walker) = motion { return !walker.isWalking }
            return false
        }
    }

    /// Whether a paired Mac that wants mascots is connected beyond this edge.
    var canHandOff: (PeerSide) -> Bool = { _ in false }
    /// Sends a mascot that walked or flew off an edge.
    var handOff: (RoamingObject, PeerSide) -> Void = { _, _ in }
    var mascot: () -> Mascot = { .cat }
    /// This Mac's device id: its own mascot carries it, so other Macs can tell it from theirs.
    var homeID = ""

    private var items: [String: Item] = [:]
    /// This Mac's own mascots that are visiting another Mac, by the edge they left through.
    private var away: [String: PeerSide] = [:]
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = Date()
    private var aloneSince: Date?
    private var dragOffset = CGVector.zero
    private var dragSamples: [(time: Date, point: NSPoint)] = []

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }
        spawn()
        lastTick = Date()
        schedule(interval: Self.frameInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerInterval = 0
        items.values.forEach { $0.panel.close() }
        items = [:]
        away = [:]
        aloneSince = nil
    }

    /// A mascot arrived from the Mac beside this one.
    func receive(_ object: RoamingObject) {
        guard isRunning, object.kind == .mascot, object.hasValidID,
              items[object.id] == nil, items.count < Self.maximumMascots else { return }
        away[object.id] = nil
        let area = geometry()
        let motion: Motion
        if let flight = object.flight {
            motion = .flying(MascotFling.arriving(flight, entry: object.entryEdge, maxX: area.maxX,
                                                  maxLift: area.maxLift, size: MascotStroll.size))
        } else {
            motion = .walking(RoamingWalker.arriving(object, maxX: area.maxX, size: MascotStroll.size,
                                                     seed: .random(in: 0...UInt64.max)))
        }
        add(id: object.id, home: object.home, look: object.look, motion: motion)
        aloneSince = nil
        schedule(interval: Self.frameInterval)
    }

    /// A paired Mac went away: its visiting mascots go home with it, so it does not come back to two of them.
    func peerLeft(_ peerID: String) {
        for item in items.values where item.home == peerID && !item.isHeld {
            item.panel.close()
            items[item.id] = nil
        }
    }

    // MARK: - Walking and flying

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), Self.maximumTickGap)
        lastTick = now
        let area = geometry()
        for id in Array(items.keys) {
            guard let item = items[id] else { continue }
            advance(item, dt: dt, area: area)
        }
        respawnIfDue(now)
        let interval = items.isEmpty ? Self.idleInterval
            : items.values.allSatisfy(\.isResting) ? Self.restingInterval : Self.frameInterval
        schedule(interval: interval)
    }

    private func advance(_ item: Item, dt: TimeInterval, area: Area) {
        var item = item
        switch item.motion {
        case .held:
            return
        case let .walking(walker):
            let (next, handoff) = walker.advanced(by: dt, maxX: area.maxX, size: MascotStroll.size, canExit: canHandOff)
            if let handoff {
                return send(item, object: handoff, side: handoff.direction.exitEdge)
            }
            item.motion = .walking(next)
        case let .flying(fling):
            switch fling.advanced(by: dt, maxX: area.maxX, maxLift: area.maxLift, size: MascotStroll.size,
                                  canExit: canHandOff) {
            case let .flying(next):
                item.motion = .flying(next)
            case let .landed(x, facesRight):
                item.motion = .walking(RoamingWalker.landed(id: item.id, x: x, facesRight: facesRight,
                                                            seed: .random(in: 0...UInt64.max)))
            case let .gone(side, flight):
                let object = RoamingObject(id: item.id, kind: .mascot, yFraction: Self.bottom,
                                           direction: side == .left ? .left : .right, state: .walking, flight: flight)
                return send(item, object: object, side: side)
            }
        }
        items[item.id] = item
        show(item, in: area)
    }

    private func send(_ item: Item, object: RoamingObject, side: PeerSide) {
        item.panel.close()
        items[item.id] = nil
        let isOwn = item.home == homeID
        if isOwn { away[item.id] = side }
        handOff(RoamingObject(id: object.id, kind: object.kind, yFraction: object.yFraction,
                              direction: object.direction, state: object.state,
                              home: item.home, look: item.look ?? ownMascot(), flight: object.flight), side)
    }

    /// This Mac always has one mascot of its own, here or visiting a Mac that is still connected.
    private func respawnIfDue(_ now: Date) {
        away = away.filter { canHandOff($0.value) }
        let hasOwn = items.values.contains { $0.home == homeID } || !away.isEmpty
        guard !hasOwn else { aloneSince = nil; return }
        let since = aloneSince ?? now
        aloneSince = since
        guard now.timeIntervalSince(since) >= Self.respawnDelay else { return }
        spawn()
        aloneSince = nil
    }

    private func spawn() {
        let id = "\(homeID.prefix(8))-\(UUID().uuidString.prefix(8))"
        let walker = RoamingWalker.spawn(id: id, yFraction: Self.bottom, maxX: geometry().maxX,
                                         seed: .random(in: 0...UInt64.max))
        add(id: id, home: homeID, look: nil, motion: .walking(walker))
    }

    private func add(id: String, home: String?, look: Mascot?, motion: Motion) {
        let sprite = DesktopMascotSprite(mascot: look ?? ownMascot(), pose: Self.pose(motion))
        let panel = DesktopMascotPanel(sprite: sprite)
        panel.onGrab = { [weak self] point in self?.grab(id, at: point) }
        panel.onDrag = { [weak self] point in self?.drag(id, to: point) }
        panel.onRelease = { [weak self] point in self?.release(id, at: point) }
        panel.onClick = { [weak self] point in self?.poke(id, at: point) }
        let item = Item(id: id, home: home, look: look, motion: motion, panel: panel, sprite: sprite)
        items[id] = item
        show(item, in: geometry())
        panel.orderFrontRegardless()
    }

    /// Visitors keep their home Mac's look; this Mac's own mascot follows the choice made here.
    private func ownMascot() -> Mascot {
        let chosen = mascot()
        return chosen == .none ? .cat : chosen
    }

    private static func pose(_ motion: Motion) -> MascotPose {
        switch motion {
        case let .walking(walker): walker.pose
        case let .flying(fling): fling.pose
        case let .held(x, _, since):
            MascotPose(x: x, facesRight: true, isWalking: false, isPickedUp: true, steps: 0,
                       elapsed: Date().timeIntervalSince(since))
        }
    }

    // MARK: - Clicking

    /// Each click builds up its mood; enough in a row and it runs off, away from the mouse.
    private func poke(_ id: String, at point: NSPoint) {
        guard var item = items[id] else { return }
        item.mood = item.mood.poked(at: Date().timeIntervalSinceReferenceDate)
        if item.mood.wantsToFlee, case let .walking(walker) = item.motion {
            let area = geometry()
            item.motion = .walking(walker.fleeing(from: Double(point.x - area.visible.minX),
                                                  size: Double(MascotStroll.size)))
            schedule(interval: Self.frameInterval)
        }
        items[id] = item
        show(item, in: geometry())
    }

    private static func face(_ item: Item, at time: TimeInterval) -> MascotFace {
        if case let .walking(walker) = item.motion, walker.isRunning { return .fleeing }
        let face = item.mood.face(at: time)
        // Only a running mascot looks scared; caught or thrown, it is just annoyed.
        return face == .fleeing ? .annoyed : face
    }

    // MARK: - Throwing

    private func grab(_ id: String, at point: NSPoint) {
        guard var item = items[id] else { return }
        let origin = item.panel.frame.origin
        dragOffset = CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
        dragSamples = [(Date(), point)]
        let area = geometry()
        item.motion = .held(x: Double(origin.x - area.visible.minX), lift: Double(origin.y - area.visible.minY),
                            since: Date())
        schedule(interval: Self.frameInterval)
        items[id] = item
        show(item, in: area)
    }

    private func drag(_ id: String, to point: NSPoint) {
        guard var item = items[id], case let .held(_, _, since) = item.motion else { return }
        let now = Date()
        dragSamples.append((now, point))
        dragSamples.removeAll { now.timeIntervalSince($0.time) > Self.throwWindow * 2 }
        let area = geometry()
        let x = min(max(Double(point.x - dragOffset.dx - area.visible.minX), 0), area.maxX)
        let lift = min(max(Double(point.y - dragOffset.dy - area.visible.minY), 0), area.maxLift)
        item.motion = .held(x: x, lift: lift, since: since)
        items[id] = item
        show(item, in: area)
    }

    private func release(_ id: String, at point: NSPoint) {
        guard var item = items[id], case let .held(x, lift, _) = item.motion else { return }
        let now = Date()
        let first = dragSamples.first { now.timeIntervalSince($0.time) <= Self.throwWindow } ?? (now, point)
        let span = max(now.timeIntervalSince(first.time), 1.0 / 120)
        let vx = Double(point.x - first.point.x) / span
        let vy = Double(point.y - first.point.y) / span
        dragSamples = []
        item.motion = .flying(MascotFling(x: x, lift: lift, vx: vx, vy: vy))
        items[id] = item
        lastTick = now
        schedule(interval: Self.frameInterval)
    }

    // MARK: - Screen

    private struct Area {
        let visible: NSRect
        var maxX: Double { max(Double(visible.width) - Double(MascotStroll.size), 0) }
        var maxLift: Double { max(Double(visible.height) - Double(MascotStroll.size), 0) }
    }

    /// The main display without the menu bar and Dock.
    private func geometry() -> Area {
        Area(visible: NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
    }

    private func show(_ item: Item, in area: Area) {
        let visible = area.visible
        let x: Double
        let lift: Double
        switch item.motion {
        case let .walking(walker): (x, lift) = (walker.x, 0)
        case let .flying(fling): (x, lift) = (fling.x, fling.lift)
        case let .held(heldX, heldLift, _): (x, lift) = (heldX, heldLift)
        }
        let origin = NSPoint(x: Double(visible.minX) + x, y: Double(visible.minY) + lift)
        // The mouse in the mascot's own view points, top-left origin, so its eyes can follow it.
        let mouse = NSEvent.mouseLocation
        let target = MascotPoint(x: Double(mouse.x - origin.x), y: Double(origin.y + MascotStroll.size - mouse.y))
        item.sprite.update(mascot: item.look ?? ownMascot(), pose: Self.pose(item.motion),
                           face: Self.face(item, at: Date().timeIntervalSinceReferenceDate), target: target)
        if item.panel.frame.origin != origin { item.panel.setFrameOrigin(origin) }
    }

    private func schedule(interval: TimeInterval) {
        guard interval != timerInterval else { return }
        timer?.invalidate()
        timerInterval = interval
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}
