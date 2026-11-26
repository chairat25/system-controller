import AppKit
import SwiftUI
import OSLog

/// Development aid for checking layout without screen-recording permission: when the app is started with
/// `SC_UI_SNAPSHOT=<folder>`, the distributed notification `com.pond.soundcontrol.uisnapshot` writes a PNG of each
/// visible window of the app into that folder. An object of the form `do:<command>` runs `perform` instead (open the
/// popup, switch a tab), so a script can walk through the pages. Without the variable nothing is installed.
@MainActor
enum UISnapshot {
    private static let notification = Notification.Name("com.pond.soundcontrol.uisnapshot")
    private static var observer: NSObjectProtocol?
    private static var folder: URL?
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "UISnapshot")

    static func installIfRequested(perform: @escaping (String) -> Void) {
        guard observer == nil, let path = ProcessInfo.processInfo.environment["SC_UI_SNAPSHOT"], !path.isEmpty else {
            return
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        self.folder = folder
        logger.notice("UI snapshots go to \(path, privacy: .public)")
        observer = DistributedNotificationCenter.default().addObserver(forName: notification, object: nil,
                                                                       queue: .main) { note in
            let label = (note.object as? String) ?? "snapshot"
            logger.notice("UI snapshot request \(label, privacy: .public)")
            MainActor.assumeIsolated {
                if label.hasPrefix("do:") { perform(String(label.dropFirst(3))) } else { capture(into: folder, label: label) }
            }
        }
    }

    /// The real popup closes as soon as another app is in front, so a script checks the same view in a plain
    /// panel that, like the popup, takes the size the view asks for.
    private static var popupCopy: NSPanel?

    static func showPopupCopy(_ view: some View) {
        popupCopy?.close()
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .nonactivatingPanel, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        popupCopy = panel
    }

    /// Writes text next to the snapshots, for a script to read the app's state.
    static func write(_ text: String, named name: String) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name))
        } catch {
            logger.error("UI snapshot text failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func capture(into folder: URL, label: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let summary = NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        logger.notice("Windows: \(summary.joined(separator: "; "), privacy: .public)")
        for (index, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 60 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = "\(label)-\(index)-\(Int(window.frame.width))x\(Int(window.frame.height)).png"
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            } catch {
                logger.error("UI snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
