import AppKit
import Observation
import SoundControlCore

/// Tracks how long the screen saver has been left alone and publishes the brightness for that idle time.
/// Moving the mouse counts as activity and brings the light back. One dimmer drives every screen.
@MainActor
@Observable
final class ScreenSaverDimmer {
    private static let pollInterval: TimeInterval = 0.5

    private(set) var brightness = 1.0

    @ObservationIgnored private let settings: ScreenSaverSettings
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var lastMouse = NSEvent.mouseLocation
    @ObservationIgnored private var timer: Timer?

    init(settings: ScreenSaverSettings) {
        self.settings = settings
    }

    func start() {
        guard timer == nil, settings.isDimEnabled else { return }
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

    private func tick() {
        let now = Date()
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastActivity = now
        }
        brightness = settings.brightness(idle: now.timeIntervalSince(lastActivity))
    }
}
