import AppKit
import Observation
import SoundControlCore

/// Tracks how long the screen saver has been left alone and publishes the brightness for that idle time.
/// Moving the mouse counts as activity and brings the light back. One dimmer drives every screen.
/// While a settings drawer is open it can show the fully dimmed look instead, so changes are seen as they are made.
@MainActor
@Observable
final class ScreenSaverDimmer {
    private static let pollInterval: TimeInterval = 0.5

    private(set) var brightness = 1.0
    /// The owner's choice in the drawers: show the dimmed look while a drawer is open.
    var isPreviewWanted = true {
        didSet { tick() }
    }

    @ObservationIgnored private let settings: @MainActor () -> ScreenSaverSettings
    @ObservationIgnored private var openDrawers = 0
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var lastMouse = NSEvent.mouseLocation
    @ObservationIgnored private var timer: Timer?

    init(settings: @escaping @MainActor () -> ScreenSaverSettings) {
        self.settings = settings
    }

    /// Runs even with dimming off, because it can be switched on from a drawer while the screen saver is up.
    func start() {
        guard timer == nil else { return }
        lastActivity = Date()
        lastMouse = NSEvent.mouseLocation
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A drawer opened or closed on some screen. Closing the last one starts the idle time over, at full light.
    func drawerChanged(isOpen: Bool) {
        openDrawers = max(openDrawers + (isOpen ? 1 : -1), 0)
        if openDrawers == 0 { lastActivity = Date() }
        tick()
    }

    private var isPreviewing: Bool { openDrawers > 0 && isPreviewWanted }

    private func tick() {
        let now = Date()
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastActivity = now
        }
        let current = settings()
        let next = isPreviewing ? current.brightness(idle: .infinity) : current.brightness(idle: now.timeIntervalSince(lastActivity))
        // Every write redraws all screens, so the steady value is only written once.
        if next != brightness { brightness = next }
    }
}
