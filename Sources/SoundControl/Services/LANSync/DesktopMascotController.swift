import AppKit
import SoundControlCore

/// Runs the desktop mascots on this Mac: spawns one, walks it, and passes it to a paired Mac when it walks off an
/// edge that has a neighbour. Panels and timers exist only between `start` and `stop`.
@MainActor
final class DesktopMascotController {
    private static let frameInterval: TimeInterval = 1.0 / 24
    private static let idleInterval: TimeInterval = 5
    private static let maximumTickGap: TimeInterval = 0.25
    /// A mascot handed to a Mac that vanished is lost; a new one appears after this long without any.
    private static let respawnDelay: TimeInterval = 60
    private static let maximumMascots = 3
    private static let bottom = 1.0

    private struct Item {
        var walker: RoamingWalker
        let panel: DesktopMascotPanel
        let sprite: DesktopMascotSprite
    }

    /// Whether a paired Mac that wants mascots is connected beyond this edge.
    var canHandOff: (PeerSide) -> Bool = { _ in false }
    /// Sends a mascot that walked off an edge.
    var handOff: (RoamingObject, PeerSide) -> Void = { _, _ in }
    var mascot: () -> Mascot = { .cat }

    private var items: [String: Item] = [:]
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = Date()
    private var emptySince: Date?

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
        emptySince = nil
    }

    /// A mascot arrived from the Mac beside this one.
    func receive(_ object: RoamingObject) {
        guard isRunning, object.kind == .mascot, object.hasValidID,
              items[object.id] == nil, items.count < Self.maximumMascots else { return }
        let walker = RoamingWalker.arriving(object, maxX: geometry().maxX, size: MascotStroll.size,
                                            seed: .random(in: 0...UInt64.max))
        add(walker)
        emptySince = nil
        schedule(interval: Self.frameInterval)
    }

    // MARK: - Walking

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), Self.maximumTickGap)
        lastTick = now
        guard !items.isEmpty else { return respawnIfDue(now) }
        let area = geometry()
        for id in Array(items.keys) {
            guard var item = items[id] else { continue }
            let (walker, handoff) = item.walker.advanced(by: dt, maxX: area.maxX, size: MascotStroll.size,
                                                         canExit: canHandOff)
            if let handoff {
                item.panel.close()
                items[id] = nil
                handOff(handoff, handoff.direction.exitEdge)
                continue
            }
            item.walker = walker
            items[id] = item
            item.sprite.update(mascot: shownMascot(), pose: walker.pose)
            place(item, in: area)
        }
        if items.isEmpty {
            emptySince = now
            schedule(interval: Self.idleInterval)
        }
    }

    private func respawnIfDue(_ now: Date) {
        let since = emptySince ?? now
        emptySince = since
        guard now.timeIntervalSince(since) >= Self.respawnDelay else { return }
        spawn()
        emptySince = nil
        schedule(interval: Self.frameInterval)
    }

    private func spawn() {
        let walker = RoamingWalker.spawn(id: UUID().uuidString, yFraction: Self.bottom, maxX: geometry().maxX,
                                         seed: .random(in: 0...UInt64.max))
        add(walker)
    }

    private func add(_ walker: RoamingWalker) {
        let sprite = DesktopMascotSprite(mascot: shownMascot(), pose: walker.pose)
        let panel = DesktopMascotPanel(sprite: sprite)
        let item = Item(walker: walker, panel: panel, sprite: sprite)
        items[walker.id] = item
        place(item, in: geometry())
        panel.orderFrontRegardless()
    }

    private func shownMascot() -> Mascot {
        let chosen = mascot()
        return chosen == .none ? .cat : chosen
    }

    // MARK: - Screen

    @MainActor
    private struct Area {
        let visible: NSRect
        var maxX: Double { max(Double(visible.width) - Double(MascotStroll.size), 0) }
    }

    /// The main display without the menu bar and Dock.
    private func geometry() -> Area {
        Area(visible: NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
    }

    private func place(_ item: Item, in area: Area) {
        let side = Double(MascotStroll.size)
        let visible = area.visible
        let top = Double(visible.maxY) - item.walker.yFraction * Double(visible.height) - side / 2
        let y = min(max(top, Double(visible.minY)), Double(visible.maxY) - side)
        let origin = NSPoint(x: Double(visible.minX) + item.walker.x, y: y)
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
