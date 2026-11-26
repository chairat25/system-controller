import AppKit
import SoundControlCore

/// Runs the desktop mascots on this Mac: keeps this Mac's own mascot alive, walks every mascot on screen, lets the
/// owner pick one up and throw it, makes it react to clicks (curious, then annoyed, then it runs away), points its
/// eyes at the mouse, and passes a mascot to a paired Mac when it walks or flies off an edge with a
/// neighbour. Visitors keep the look of their home Mac. Panels and timers exist only between `start` and `stop`.
@MainActor
final class DesktopMascotController {
    private static let idleInterval: TimeInterval = 5
    private static let maximumTickGap: TimeInterval = 0.25
    /// This Mac's mascot handed to a Mac that vanished is lost; a new one appears after this long.
    private static let respawnDelay: TimeInterval = 60
    /// Own mascots (up to six) and the babies born here together.
    private static let maximumMascots = 12
    /// Visitors from paired computers on top of that, so a full screen still takes a friend in.
    private static let maximumVisitors = 8
    private static let bottom = 1.0
    /// Only the last moments of a drag decide the throw.
    private static let throwWindow: TimeInterval = 0.08

    private enum Motion {
        case walking(RoamingWalker)
        case held(x: Double, lift: Double, since: Date)
        case flying(MascotFling)
        /// Up the side of another app's window, or strolling along its top edge.
        case climbing(WindowClimber)
    }

    private struct Item {
        let id: String
        let home: String?
        let look: Mascot?
        /// A visitor's colour and size from its home; nil for this Mac's own, which follow the style chosen here.
        let visitorHue: Double?
        let visitorScale: Double?
        var motion: Motion
        var mood = MascotMood.calm
        /// What the society last asked it to do: nap, hop, greet, play, follow, court.
        var order = MascotOrder.free
        /// When it was born on this desktop; nil for the ones that came with the app or from another Mac.
        let bornAt: Date?
        let panel: DesktopMascotPanel
        let sprite: DesktopMascotSprite

        var isHeld: Bool {
            if case .held = motion { return true }
            return false
        }

        /// In the hand or in the air: moves fast, so it runs at the display's own frame rate.
        var isAirborne: Bool {
            switch motion {
            case .held, .flying: return true
            case .walking, .climbing: return false
            }
        }

        /// Resting on the floor: nothing moves but breathing and blinks.
        var isResting: Bool {
            if case let .walking(walker) = motion { return !walker.isWalking && !order.hops }
            return false
        }
    }

    /// Whether a paired Mac that wants mascots is connected beyond this edge.
    var canHandOff: (PeerSide) -> Bool = { _ in false }
    /// Sends a mascot that walked or flew off an edge.
    var handOff: (RoamingObject, PeerSide) -> Void = { _, _ in }
    var mascot: () -> Mascot = { .cat }
    /// This Mac's choice of frame rate while a mascot is held or flying.
    var throwFrameRate: () -> ThrowFrameRate = { .default }
    /// How hard the app may work: frame rates drop and climbing stops when the Mac is hot, busy or short of memory.
    var budget: () -> ResourceBudget = { .full }
    /// Size, number and colour of this Mac's own mascots.
    var style: () -> MascotStyle = { .default }
    /// This Mac's device id: its own mascot carries it, so other Macs can tell it from theirs.
    var homeID = ""

    private var items: [String: Item] = [:]
    /// Decides what each mascot does and when a baby is born.
    private var society = MascotSociety(seed: .random(in: 0...UInt64.max))
    /// This Mac's own mascots that are visiting another Mac, by the edge they left through.
    private var away: [String: PeerSide] = [:]
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = Date()
    private var aloneSince: Date?
    private var dragOffset = CGVector.zero
    private var dragSamples: [(time: Date, point: NSPoint)] = []
    private let windows = WindowSurfaces()
    /// After a climb, or after deciding not to, a mascot walks on for a while before it may climb again.
    private var climbRestUntil: [String: Date] = [:]

    var isRunning: Bool { isStarted }
    private var isStarted = false
    /// True while the screen saver covers the desktop: no frames are drawn, nothing moves.
    private(set) var isPaused = false

    /// Stops animating while nothing on the desktop can be seen, and carries on where it was afterwards.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
        } else if isStarted {
            lastTick = Date()
            schedule(interval: budget().walkingInterval)
        }
    }

    /// The side of a mascot's box in points: the normal size times this Mac's size choice.
    private var side: CGFloat { MascotStroll.size * CGFloat(style().scale) }

    func start() {
        guard !isRunning else { return }
        isStarted = true
        society = MascotSociety(seed: .random(in: 0...UInt64.max))
        for _ in 0..<style().count { spawn() }
        lastTick = Date()
        schedule(interval: budget().walkingInterval)
    }

    /// The owner changed the size, number or colour: resize the boxes, add or take away own mascots, redraw.
    func applyStyle() {
        guard isRunning else { return }
        let side = self.side
        for item in items.values where item.panel.contentView?.frame.width != side {
            item.panel.setContentSize(NSSize(width: side, height: side))
        }
        reconcileOwnCount()
        let area = geometry()
        for item in items.values { show(item, in: area) }
        schedule(interval: budget().walkingInterval)
    }

    /// Brings the number of this Mac's own mascots, here or visiting, to the chosen one. A mascot in the hand stays.
    private func reconcileOwnCount() {
        let target = style().count
        let own = items.values.filter { $0.home == homeID && $0.bornAt == nil }
        var present = own.count + away.count
        while present < target {
            spawn()
            present += 1
        }
        for item in own where present > target && !item.isHeld {
            item.panel.close()
            items[item.id] = nil
            present -= 1
        }
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        timerInterval = 0
        items.values.forEach { $0.panel.close() }
        items = [:]
        away = [:]
        climbRestUntil = [:]
        aloneSince = nil
    }

    /// A mascot arrived from the computer beside this one. False when it cannot stay (not running, screen full),
    /// so the caller sends it back instead of it vanishing on the way.
    @discardableResult
    func receive(_ object: RoamingObject) -> Bool {
        guard object.kind == .mascot, object.hasValidID else { return true }
        guard isRunning, items[object.id] == nil else { return items[object.id] != nil }
        let visitors = items.values.filter { $0.home != homeID }.count
        guard object.home == homeID || visitors < Self.maximumVisitors else { return false }
        place(object)
        return true
    }

    /// A mascot of this Mac's was sent back by the computer it walked to: it comes back in through that edge.
    func returned(_ object: RoamingObject, from side: PeerSide) {
        guard isRunning, object.kind == .mascot, object.hasValidID, items[object.id] == nil else { return }
        let back = RoamingObject(id: object.id, kind: object.kind, yFraction: object.yFraction,
                                 direction: side == .left ? .right : .left, state: .walking, home: object.home,
                                 look: object.home == homeID ? nil : object.look, hue: object.hue, scale: object.scale)
        place(back)
    }

    private func place(_ object: RoamingObject) {
        away[object.id] = nil
        let isOwn = object.home == homeID
        let scale = isOwn ? style().scale : (object.scale ?? 1)
        let side = MascotStroll.size * CGFloat(scale)
        let area = geometry().sized(side)
        let motion: Motion
        if let flight = object.flight {
            motion = .flying(MascotFling.arriving(flight, entry: object.entryEdge, maxX: area.maxX,
                                                  maxLift: area.maxLift, size: side))
        } else {
            motion = .walking(RoamingWalker.arriving(object, maxX: area.maxX, size: side,
                                                     seed: .random(in: 0...UInt64.max)))
        }
        add(id: object.id, home: object.home, look: isOwn ? nil : object.look, motion: motion,
            visitorHue: isOwn ? nil : (object.hue ?? 0), visitorScale: isOwn ? nil : scale)
        reconcileOwnCount()
        aloneSince = nil
        schedule(interval: object.flight == nil ? budget().walkingInterval : displayInterval())
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
        retireOldBorn(now)
        socialize(now: now, dt: dt)
        for id in Array(items.keys) {
            guard let item = items[id] else { continue }
            advance(item, dt: dt, area: area.sized(side(for: item, now: now)))
        }
        respawnIfDue(now)
        let interval = items.isEmpty ? Self.idleInterval
            : items.values.contains(where: \.isAirborne) ? displayInterval()
            : items.values.allSatisfy(\.isResting) ? budget().restingInterval : budget().walkingInterval
        schedule(interval: interval)
    }

    private func advance(_ item: Item, dt: TimeInterval, area: Area) {
        var item = item
        switch item.motion {
        case .held:
            return
        case let .walking(walker) where item.order.move == .free:
            if let climber = climbStart(item, walker: walker, area: area) {
                item.motion = .climbing(climber)
                break
            }
            fallthrough
        case let .walking(walker):
            let (next, handoff) = ordered(walker, by: item.order, side: area.side)
                .advanced(by: dt, maxX: area.maxX, size: Double(area.side), canExit: canHandOff)
            if let handoff {
                return send(item, object: handoff, side: handoff.direction.exitEdge)
            }
            item.motion = .walking(next)
        case let .climbing(climber):
            switch climber.advanced(by: dt, surfaces: climbSurfaces(area), size: Double(area.side)) {
            case let .climbing(next): item.motion = .climbing(next)
            case let .jumped(fling):
                climbRestUntil[item.id] = Date().addingTimeInterval(Self.climbRest)
                item.motion = .flying(fling)
            }
        case let .flying(fling):
            switch fling.advanced(by: dt, maxX: area.maxX, maxLift: area.maxLift, size: Double(area.side),
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
        let isOwn = item.home == homeID && item.bornAt == nil
        if isOwn { away[item.id] = side }
        handOff(RoamingObject(id: object.id, kind: object.kind, yFraction: object.yFraction,
                              direction: object.direction, state: object.state,
                              home: item.home, look: item.look ?? ownMascot(), flight: object.flight,
                              hue: hue(for: item), scale: scale(for: item)), side)
    }

    /// This Mac always has one mascot of its own, here or visiting a Mac that is still connected.
    private func respawnIfDue(_ now: Date) {
        away = away.filter { canHandOff($0.value) }
        let hasOwn = items.values.contains { $0.home == homeID && $0.bornAt == nil } || !away.isEmpty
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

    private func add(id: String, home: String?, look: Mascot?, motion: Motion, bornAt: Date? = nil,
                     visitorHue: Double? = nil, visitorScale: Double? = nil) {
        let base = visitorScale.map { MascotStroll.size * CGFloat($0) } ?? side
        let grown = base * CGFloat(bornAt.map { MascotGrowth.scale(age: Date().timeIntervalSince($0)) } ?? 1)
        let sprite = DesktopMascotSprite(mascot: look ?? ownMascot(), pose: Self.pose(motion), size: Double(grown),
                                         hue: visitorHue ?? (home == homeID ? style().hue : 0))
        let panel = DesktopMascotPanel(sprite: sprite, side: grown)
        panel.onGrab = { [weak self] point in self?.grab(id, at: point) }
        panel.onDrag = { [weak self] point in self?.drag(id, to: point) }
        panel.onRelease = { [weak self] point in self?.release(id, at: point) }
        panel.onClick = { [weak self] point in self?.poke(id, at: point) }
        let item = Item(id: id, home: home, look: look, visitorHue: visitorHue, visitorScale: visitorScale,
                        motion: motion, bornAt: bornAt, panel: panel, sprite: sprite)
        items[id] = item
        show(item, in: geometry())
        panel.orderFrontRegardless()
    }

    /// This Mac's own mascots take its colour and size; visitors keep their home's.
    private func hue(for item: Item) -> Double { item.visitorHue ?? (item.home == homeID ? style().hue : 0) }
    private func scale(for item: Item) -> Double { item.visitorScale ?? style().scale }

    /// Visitors keep their home Mac's look; this Mac's own mascot follows the choice made here.
    private func ownMascot() -> Mascot {
        let chosen = mascot()
        return chosen == .none ? .cat : chosen
    }

    private static func pose(_ motion: Motion) -> MascotPose {
        switch motion {
        case let .walking(walker): walker.pose
        case let .flying(fling): fling.pose
        case let .climbing(climber): climber.pose
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
                                                  size: Double(side)))
            schedule(interval: budget().walkingInterval)
        }
        items[id] = item
        show(item, in: geometry())
    }

    private static func face(_ item: Item, at time: TimeInterval) -> MascotFace {
        if case let .walking(walker) = item.motion, walker.isRunning, item.order.face == nil { return .fleeing }
        let face = item.mood.face(at: time)
        if face == .calm, let ordered = item.order.face { return ordered }
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
        schedule(interval: displayInterval())
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
        schedule(interval: displayInterval())
    }

    /// One line per mascot for a layout-check script: id, home, look, what it is doing and where.
    var debugSummary: [String] {
        let area = geometry()
        let surfaces = windows.surfaces(in: area.visible, maxLift: area.maxLift).map {
            "surface \($0.id) x=\(Int($0.minX))...\(Int($0.maxX)) bottom=\(Int($0.bottom)) top=\(Int($0.top))"
        }
        return surfaces + items.values.map { item in
            let motion: String
            switch item.motion {
            case let .walking(walker): motion = "walking x=\(Int(walker.x))"
            case let .held(x, lift, _): motion = "held x=\(Int(x)) lift=\(Int(lift))"
            case let .flying(fling): motion = "flying x=\(Int(fling.x)) lift=\(Int(fling.lift))"
            case let .climbing(climber):
                motion = "climbing x=\(Int(climber.x)) lift=\(Int(climber.lift)) top=\(climber.isOnTop)"
            }
            let look = (item.look ?? ownMascot()).rawValue
            return "\(item.id) home=\(item.home ?? "-") look=\(look) hue=\(Int(hue(for: item))) scale=\(scale(for: item)) \(motion)"
        }.sorted()
    }

    /// Layout-check scripts: one own mascot on the floor leaves through `side` now, if a neighbour is there.
    func debugPush(to side: PeerSide) {
        guard canHandOff(side), let item = items.values.first(where: {
            guard case .walking = $0.motion else { return false }
            return $0.home == homeID && $0.bornAt == nil
        }) else { return }
        let object = RoamingObject(id: item.id, kind: .mascot, yFraction: Self.bottom,
                                   direction: side == .left ? .left : .right, state: .walking)
        send(item, object: object, side: side)
    }

    // MARK: - Climbing

    /// How long a mascot walks on after a climb, or after passing a window it chose not to climb.
    private static let climbRest: TimeInterval = 20
    /// The share of windows met on the way that it climbs.
    private static let climbChance = 0.45

    /// A walking mascot that meets the side of a window on the floor sometimes climbs it.
    private func climbStart(_ item: Item, walker: RoamingWalker, area: Area) -> WindowClimber? {
        let now = Date()
        guard budget().allowsClimbing,
              item.bornAt == nil || MascotGrowth.isAdult(age: now.timeIntervalSince(item.bornAt ?? now)),
              climbRestUntil[item.id].map({ now >= $0 }) ?? true,
              let surface = WindowClimber.surface(ahead: walker, in: climbSurfaces(area), size: Double(area.side))
        else { return nil }
        climbRestUntil[item.id] = now.addingTimeInterval(Self.climbRest)
        guard Double.random(in: 0..<1) < Self.climbChance else { return nil }
        let size = Double(area.side)
        return WindowClimber.start(on: surface, facingRight: walker.facesRight, size: size,
                                   seed: .random(in: 0...UInt64.max),
                                   front: walker.facesRight ? walker.x + size : walker.x)
    }

    /// Windows with their sides kept a half mascot inside the screen, so one climbing a window as wide as the
    /// screen stays fully visible.
    private func climbSurfaces(_ area: Area) -> [ClimbSurface] {
        let half = Double(area.side) / 2
        return windows.surfaces(in: area.visible, maxLift: area.maxLift).compactMap { surface in
            let minX = max(surface.minX, half)
            let maxX = min(surface.maxX, area.maxX + half)
            guard maxX - minX >= Double(area.side) else { return nil }
            return ClimbSurface(id: surface.id, minX: minX, maxX: maxX, bottom: surface.bottom, top: surface.top)
        }
    }

    // MARK: - Screen

    private struct Area {
        let visible: NSRect
        let side: CGFloat
        func sized(_ side: CGFloat) -> Area { Area(visible: visible, side: side) }
        var maxX: Double { max(Double(visible.width) - Double(side), 0) }
        var maxLift: Double { max(Double(visible.height) - Double(side), 0) }
    }

    /// The main display without the menu bar and Dock.
    private func geometry() -> Area {
        Area(visible: NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900), side: side)
    }

    /// One frame while held or flying, at the chosen rate, never faster than the display the mascots are on.
    private func displayInterval() -> TimeInterval {
        budget().airborneInterval(display: throwFrameRate().interval(displayFPS: NSScreen.screens.first?.maximumFramesPerSecond ?? 0))
    }

    private func show(_ item: Item, in area: Area) {
        let now = Date()
        let area = area.sized(side(for: item, now: now))
        if item.panel.contentView?.frame.width != area.side {
            item.panel.setContentSize(NSSize(width: area.side, height: area.side))
        }
        let visible = area.visible
        let x: Double
        let lift: Double
        switch item.motion {
        case let .walking(walker): (x, lift) = (walker.x, hopLift(item.order, side: area.side, at: now))
        case let .flying(fling): (x, lift) = (fling.x, fling.lift)
        case let .climbing(climber): (x, lift) = (climber.x, climber.lift)
        case let .held(heldX, heldLift, _): (x, lift) = (heldX, heldLift)
        }
        let origin = NSPoint(x: Double(visible.minX) + x, y: Double(visible.minY) + lift)
        // The mouse in the mascot's own view points, top-left origin, so its eyes can follow it.
        let mouse = NSEvent.mouseLocation
        let target = MascotPoint(x: Double(mouse.x - origin.x), y: Double(origin.y + area.side - mouse.y))
        item.sprite.update(mascot: item.look ?? ownMascot(), pose: Self.pose(item.motion),
                           face: Self.face(item, at: Date().timeIntervalSinceReferenceDate), target: target,
                           size: Double(area.side), hue: hue(for: item))
        if item.panel.frame.origin != origin { item.panel.setFrameOrigin(origin) }
    }

    // MARK: - Life

    /// A mascot's box: the normal size, this Mac's size choice, and how much of a baby it still is.
    private func side(for item: Item, now: Date) -> CGFloat {
        let full = MascotStroll.size * CGFloat(scale(for: item))
        guard let bornAt = item.bornAt else { return full }
        return full * CGFloat(MascotGrowth.scale(age: now.timeIntervalSince(bornAt)))
    }

    private func hopLift(_ order: MascotOrder, side: CGFloat, at now: Date) -> Double {
        guard order.hops else { return 0 }
        return abs(sin(now.timeIntervalSinceReferenceDate * 9)) * Double(side) * 0.16
    }

    /// The walker doing what the society asked: standing for a nap or a hello, or heading for a friend.
    private func ordered(_ walker: RoamingWalker, by order: MascotOrder, side: CGFloat) -> RoamingWalker {
        switch order.move {
        case .free: walker
        case let .stand(facesRight): walker.standing(facesRight: facesRight)
        case let .go(target, running): walker.heading(towardX: target, size: Double(side), running: running)
        }
    }

    private func member(for item: Item, now: Date) -> MascotMember {
        let half = Double(side(for: item, now: now)) / 2
        let x: Double
        var isFree = false
        switch item.motion {
        case let .walking(walker):
            x = walker.x + half
            isFree = walker.phase == .inside && item.mood.face(at: now.timeIntervalSinceReferenceDate) == .calm
        case let .flying(fling): x = fling.x + half
        case let .climbing(climber): x = climber.x + half
        case let .held(heldX, _, _): x = heldX + half
        }
        let isBaby = item.bornAt.map { !MascotGrowth.isAdult(age: now.timeIntervalSince($0)) } ?? false
        return MascotMember(id: item.id, x: x, species: item.look ?? ownMascot(), home: item.home, isBaby: isBaby,
                            isFree: isFree)
    }

    /// Lets the mascots live: they pick what to do, meet each other, and sometimes a baby is born.
    private func socialize(now: Date, dt: TimeInterval) {
        let members = items.values.map { member(for: $0, now: now) }
        let bornCount = items.values.filter { $0.bornAt != nil }.count
        let canBreed = bornCount < MascotGrowth.maximumBorn && items.count < Self.maximumMascots
        let result = society.step(dt: dt, members: members, canBreed: canBreed)
        for (id, order) in result.orders { items[id]?.order = order }
        for birth in result.births { spawnBaby(birth, now: now) }
    }

    private func spawnBaby(_ birth: MascotBirth, now: Date) {
        let id = "\(homeID.prefix(8))-\(UUID().uuidString.prefix(8))"
        let babySide = Double(side) * MascotGrowth.babyScale
        let x = min(max(birth.x - babySide / 2, 0), geometry().sized(CGFloat(babySide)).maxX)
        let walker = RoamingWalker.landed(id: id, x: x, facesRight: .random(), seed: .random(in: 0...UInt64.max))
        add(id: id, home: birth.home, look: birth.home == homeID ? nil : birth.species, motion: .walking(walker),
            bornAt: now)
    }

    /// A mascot born here stays for a while, then wanders off for good. The one in the hand is left alone.
    private func retireOldBorn(_ now: Date) {
        for item in Array(items.values) where !item.isHeld {
            guard let bornAt = item.bornAt, now.timeIntervalSince(bornAt) > MascotGrowth.lifespan else { continue }
            item.panel.close()
            items[item.id] = nil
        }
    }

    private func schedule(interval: TimeInterval) {
        guard !isPaused, interval != timerInterval else { return }
        timer?.invalidate()
        timerInterval = interval
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}
