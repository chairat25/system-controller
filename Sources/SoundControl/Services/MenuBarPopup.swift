import AppKit
import ObjCExceptionCatcher

/// Opens or closes the menu-bar popup from code, as if its icon was clicked.
/// SwiftUI's `MenuBarExtra` has no API for this, so the status item is found on the window AppKit puts in the menu bar.
@MainActor
enum MenuBarPopup {
    private static let statusBarWindowClass = "NSStatusBarWindow"

    /// False when the status item could not be found, for example after a macOS change to these private classes.
    @discardableResult
    static func toggle() -> Bool {
        guard let button = statusItem()?.button else { return false }
        NSApp.activate()
        button.performClick(nil)
        return true
    }

    private static func statusItem() -> NSStatusItem? {
        for window in NSApp.windows where NSStringFromClass(type(of: window)) == statusBarWindowClass {
            var item: NSStatusItem?
            // `statusItem` is private; a missing key raises an Objective-C exception, caught here instead of crashing.
            _ = SCTryObjC({ item = window.value(forKey: "statusItem") as? NSStatusItem }, nil)
            if let item { return item }
        }
        return nil
    }
}
