import AppKit
import SwiftUI

/// The full Sound Control window. Built when it opens and dropped when it closes, so a closed window keeps no
/// SwiftUI views, layers or backing stores in memory. (A SwiftUI `Window` scene keeps its whole view tree alive
/// after closing and keeps redrawing it on every model change; after a day that grew the app past 250 MB.)
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private static let defaultSize = NSSize(width: 980, height: 720)
    private static let autosaveName = "main"

    private var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: MainWindow().environment(model))
        host.sizingOptions = [.minSize]
        let next = NSWindow(contentViewController: host)
        next.title = "System Controller"
        next.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        next.isReleasedWhenClosed = false
        next.delegate = self
        next.setContentSize(Self.defaultSize)
        if !next.setFrameUsingName(Self.autosaveName) { next.center() }
        next.setFrameAutosaveName(Self.autosaveName)
        window = next
        // Show in the Dock and app switcher only while the window is open.
        NSApp.setActivationPolicy(.regular)
        next.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
        NSApp.setActivationPolicy(.accessory)
        // Hand the hosting controller its last run-loop turn before it goes, then give its pages back.
        DispatchQueue.main.async {
            closing.contentViewController = nil
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
