import AppKit
import SwiftUI

/// The menu-bar icon and the popup under it, built with AppKit instead of SwiftUI's `MenuBarExtra`.
///
/// `MenuBarExtra` has no way to open its popup from code, and on current macOS its button has no target or action
/// (the system draws menu-bar items in its own process), so the popup shortcut could not open it. Here the icon's
/// click and the shortcut both call `toggle()`. The popup is a non-activating panel: it takes the keyboard without
/// pulling the app in front first; the app is then brought forward so keys like Escape reach it.
@MainActor
final class MenuBarPopup: NSObject, NSWindowDelegate {
    static let shared = MenuBarPopup()

    private static let symbol = "slider.horizontal.3"
    private static let cornerRadius: CGFloat = 12
    /// Gap between the menu bar and the top of the popup.
    private static let gap: CGFloat = 6
    /// Margin kept from the screen's sides.
    private static let screenMargin: CGFloat = 8
    /// A click on the icon that closes the popup also takes the key away from it first; that close must not be
    /// followed by the click opening it again.
    private static let reopenGuard: TimeInterval = 0.3
    /// How long after opening a lost focus is taken back instead of closing the popup.
    private static let settleTime: TimeInterval = 0.5

    private var statusItem: NSStatusItem?
    private var panel: PopupPanel?
    private var host: NSHostingController<AnyView>?
    private var sizeObservation: NSKeyValueObservation?
    private var closedAt = Date.distantPast
    private var openedAt = Date.distantPast

    var isOpen: Bool { panel?.isVisible ?? false }

    func install(model: AppModel) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: Self.symbol, accessibilityDescription: "System Controller")
        item.button?.target = self
        item.button?.action = #selector(iconClicked)
        statusItem = item

        let host = NSHostingController(rootView: AnyView(MenuBarView().environment(model)))
        host.sizingOptions = [.preferredContentSize]
        self.host = host
        panel = makePanel(content: host)
        sizeObservation = host.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    /// Opens the popup, or closes it when it is open. False when the icon is not installed yet.
    @discardableResult
    func toggle() -> Bool {
        guard panel != nil else { return false }
        if isOpen { close() } else { open() }
        return true
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        closedAt = Date()
        statusItem?.button?.highlight(false)
    }

    @objc private func iconClicked() {
        guard Date().timeIntervalSince(closedAt) > Self.reopenGuard else { return }
        toggle()
    }

    private func open() {
        guard let panel else { return }
        layout()
        // Keys (Escape, typing a shortcut, Cmd-Q) reach only the active app, so the app comes forward with the popup.
        openedAt = Date()
        activate()
        panel.makeKeyAndOrderFront(nil)
        statusItem?.button?.highlight(true)
    }

    /// The plain `activate()` is a request the front app may refuse when the shortcut is pressed in it; asking on
    /// behalf of that app, and then the older forceful call, brings this one forward.
    private func activate() {
        guard !NSApp.isActive else { return }
        NSRunningApplication.current.activate(from: NSWorkspace.shared.frontmostApplication ?? .current, options: [])
        if !NSApp.isActive { Self.activateIgnoringOtherApps() }
    }

    @available(macOS, deprecated: 14)
    private static func activateIgnoringOtherApps() {
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Panel

    private func makePanel(content: NSViewController) -> PopupPanel {
        let panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true
        content.view.frame = background.bounds
        content.view.autoresizingMask = [.width, .height]
        background.addSubview(content.view)
        panel.contentView = background
        return panel
    }

    /// Sizes the panel to the page and hangs it under the icon, kept on the icon's screen.
    private func layout() {
        guard let panel, let host else { return }
        let size = host.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        let anchor = iconFrame()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + Self.screenMargin),
                    visible.maxX - size.width - Self.screenMargin)
        let top = visible.maxY - Self.gap
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// The icon on the screen where the pointer is (each display shows its own copy of the menu bar), or the
    /// icon's own frame when the pointer is elsewhere.
    private func iconFrame() -> NSRect {
        let own = statusItem?.button?.window?.frame ?? .zero
        let mouse = NSEvent.mouseLocation
        guard let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return own }
        if mouseScreen.frame.contains(NSPoint(x: own.midX, y: own.midY)) { return own }
        // On another display the icon sits the same distance from the right edge.
        let fromRight = (NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: own.midX, y: own.midY)) })?
            .frame.maxX ?? own.maxX) - own.midX
        let midX = mouseScreen.frame.maxX - fromRight
        return NSRect(x: midX - own.width / 2, y: mouseScreen.frame.maxY - own.height, width: own.width, height: own.height)
    }

    // MARK: - NSWindowDelegate

    /// Clicking anywhere else (another app, the desktop, a menu-bar item) takes the key from the popup: it closes,
    /// as a menu would.
    func windowDidResignKey(_ notification: Notification) {
        // Opening from a shortcut pressed in another app, that app can take the focus back a moment later while the
        // activation settles. That is not the owner clicking away, so the popup takes the key again.
        if Date().timeIntervalSince(openedAt) < Self.settleTime, let panel, panel.isVisible {
            activate()
            panel.makeKey()
            return
        }
        close()
    }
}

/// A borderless panel that can still take the keyboard, and closes on Escape.
final class PopupPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
