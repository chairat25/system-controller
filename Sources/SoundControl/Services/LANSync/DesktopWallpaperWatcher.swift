import AppKit

/// Notices when the desktop wallpaper of the main display changes. It polls only between `start` and `stop`.
final class DesktopWallpaperWatcher {
    private static let pollInterval: TimeInterval = 5
    private static let pollTolerance: TimeInterval = 2

    /// Called with the new wallpaper file when the user (not this app) changed it.
    var onChange: ((URL) -> Void)?

    private var timer: Timer?
    private var lastSignature: String?

    var isRunning: Bool { timer != nil }

    /// The first look only records the current wallpaper as the baseline.
    func start() {
        guard timer == nil else { return }
        lastSignature = Self.signature().signature
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = Self.pollTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSignature = nil
    }

    /// Call after this app sets the wallpaper itself, so the change is not mistaken for the user's.
    func markSeen() {
        guard timer != nil else { return }
        lastSignature = Self.signature().signature
    }

    private func poll() {
        let (signature, url) = Self.signature()
        guard signature != lastSignature else { return }
        lastSignature = signature
        if let url { onChange?(url) }
    }

    /// The path and modification date of the main display's wallpaper file.
    private static func signature() -> (signature: String?, url: URL?) {
        guard let screen = NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return (nil, nil) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ("\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)", url)
    }
}
