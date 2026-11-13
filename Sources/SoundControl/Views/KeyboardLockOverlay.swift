import AppKit
import CoreFoundation
import Darwin
import SwiftUI
import SoundControlCore

/// One dimmed panel per screen above everything (menu bar, Dock, and macOS system popups included),
/// so stray trackpad clicks and system notifications/alerts cannot break through the screen saver.
/// The owner lock shows the Smartheart Screen Saver on every screen; the cleaning lock shows a plain lock screen.
@MainActor
final class KeyboardLockOverlay {
    private var panels: [NSPanel] = []
    private var drawers: [DrawerState] = []
    private let dimmer: ScreenSaverDimmer
    private let lock: KeyboardLock
    private let link: ScreenSaverLink
    private let sessions: ClaudeSessionMonitor?
    private let onUnlock: @MainActor () -> Void
    private let onPasswordPrompt: @MainActor () -> Void
    private let scanController: OwnerScanController
    private var shieldSpace: SkyLightShieldSpace?
    private var scrollMonitor: Any?
    private var swipe = SwipeTracker.initial
    /// One swipe moves a drawer once, however long the fingers keep going.
    private var isSwipeUsed = false
    private var savedPresentation: NSApplication.PresentationOptions = []
    private var isPasswordPromptActive = false
    private var shieldTimer: Timer?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Above `.screenSaver` (1000), `.assistiveTechHighWindow` (1500), Notification Center banners and TCC alerts,
    /// while still below `.cursorWindow` so the mouse pointer stays visible.
    private static let shieldLevel = NSWindow.Level(Int(CGShieldingWindowLevel()))
    private static let shieldPollInterval: TimeInterval = 0.5
    private static let statusBarWindowClass = "NSStatusBarWindow"
    private static let fallbackBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]

    /// Kiosk mode while locked. Hiding the Dock also turns off the Dock's gestures: three-finger swipes
    /// between Spaces and Mission Control, which otherwise slide the desktop and the Dock into view.
    private static let kioskPresentation: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication, .disableAppleMenu
    ]

    init(lock: KeyboardLock,
         link: ScreenSaverLink,
         sessions: ClaudeSessionMonitor?,
         onUnlock: @escaping @MainActor () -> Void,
         onPasswordPrompt: @escaping @MainActor () -> Void) {
        let dimmer = ScreenSaverDimmer(settings: link.read)
        self.dimmer = dimmer
        self.lock = lock
        self.link = link
        self.sessions = sessions
        self.onUnlock = onUnlock
        self.onPasswordPrompt = onPasswordPrompt
        let screens = NSScreen.screens
        let initialScreen = Self.preferredScreenIndex(in: screens)
        self.scanController = OwnerScanController(
            activeScreenIndex: initialScreen,
            onUnlock: onUnlock,
            onPasswordPrompt: onPasswordPrompt
        )
        self.shieldSpace = SkyLightShieldSpace()
        buildPanels(for: screens)
        for window in NSApp.windows where !panels.contains(where: { $0 === window })
            && NSStringFromClass(type(of: window)) != Self.statusBarWindowClass {
            window.orderOut(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        savedPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = Self.kioskPresentation
        presentPanels(keyIndex: initialScreen)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.attachToShieldSpaceIfNeeded() }
        }
        installShieldGuards()
        if lock.unlock == .ownerAuthentication {
            dimmer.start()
            watchSwipes()
        }
    }

    func setPasswordPromptActive(_ isActive: Bool) {
        isPasswordPromptActive = isActive
        if isActive {
            shieldSpace?.detach(windowNumbers: panels.map(\.windowNumber))
            panels.forEach {
                $0.collectionBehavior = Self.fallbackBehavior
                $0.level = .normal
            }
        } else {
            if shieldSpace != nil {
                panels.forEach { $0.collectionBehavior = [] }
            }
            attachToShieldSpace()
            enforceShield(forceOrderFront: true)
            scanController.resumeAfterPasswordCancel()
        }
    }

    func close() {
        shieldTimer?.invalidate()
        shieldTimer = nil
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appObservers = []
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        scanController.stopScan()
        dimmer.stop()
        NSApp.presentationOptions = savedPresentation
        shieldSpace?.destroy(windowNumbers: panels.map(\.windowNumber))
        shieldSpace = nil
        panels.forEach { $0.close() }
    }

    private static func preferredScreenIndex(in screens: [NSScreen]) -> Int {
        guard !screens.isEmpty else { return 0 }
        let mouseLocation = NSEvent.mouseLocation
        if let pointerIndex = screens.firstIndex(where: { $0.frame.contains(mouseLocation) }) {
            return pointerIndex
        }
        if let main = NSScreen.main, let mainIndex = screens.firstIndex(of: main) {
            return mainIndex
        }
        return 0
    }

    private func buildPanels(for screens: [NSScreen]) {
        let drawers = screens.map { _ in DrawerState { [weak dimmer] isOpen in dimmer?.drawerChanged(isOpen: isOpen) } }
        self.drawers = drawers
        panels = screens.enumerated().map { index, screen in
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
            panel.level = Self.shieldLevel
            panel.hidesOnDeactivate = false
            panel.worksWhenModal = true
            // Both lock screens paint solid black edge to edge, so an opaque panel skips alpha compositing.
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            // Non-default collectionBehavior causes AppKit to reset CGS space assignments on the next run-loop turn.
            // Keep default [] whenever SkyLightShieldSpace manages the space; only use fallback behavior otherwise.
            if shieldSpace == nil {
                panel.collectionBehavior = Self.fallbackBehavior
            }
            panel.contentView = NSHostingView(rootView: KeyboardLockView(lock: lock, link: link, dimmer: dimmer,
                                                                         drawer: drawers[index], sessions: sessions,
                                                                         display: screen,
                                                                         screenIndex: index,
                                                                         scanController: scanController,
                                                                         onUnlock: onUnlock,
                                                                         onPasswordPrompt: onPasswordPrompt))
            panel.setFrame(screen.frame, display: true)
            return panel
        }
    }

    private func presentPanels(keyIndex: Int) {
        panels.forEach { $0.orderFrontRegardless() }
        let targetPanel = panels.indices.contains(keyIndex) ? panels[keyIndex] : panels.first
        targetPanel?.makeKeyAndOrderFront(nil)
        attachToShieldSpace()
    }

    private func attachToShieldSpace() {
        shieldSpace?.attach(windowNumbers: panels.map(\.windowNumber))
    }

    private func attachToShieldSpaceIfNeeded() {
        guard !isPasswordPromptActive else { return }
        attachToShieldSpace()
    }

    private func installShieldGuards() {
        let appCenter = NotificationCenter.default
        appObservers = [
            appCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enforceShield(forceOrderFront: true) }
            },
            appCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.realignAndEnforceShield() }
            },
            appCenter.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          !self.isPasswordPromptActive,
                          let window = note.object as? NSWindow,
                          let index = self.panels.firstIndex(where: { $0 === window }) else { return }
                    self.scanController.setActiveScreen(index)
                }
            }
        ]
        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated { self?.enforceShield(forceOrderFront: true) }
            },
            wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enforceShield(forceOrderFront: true) }
            }
        ]
        shieldTimer = Timer.scheduledTimer(withTimeInterval: Self.shieldPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforceShield() }
        }
    }

    private func realignAndEnforceShield() {
        let screens = NSScreen.screens
        if screens.count != panels.count {
            shieldSpace?.detach(windowNumbers: panels.map(\.windowNumber))
            panels.forEach { $0.close() }
            let nextActive = Self.preferredScreenIndex(in: screens)
            scanController.rearmForScreenChange(activeScreenIndex: nextActive)
            buildPanels(for: screens)
            presentPanels(keyIndex: nextActive)
            enforceShield(forceOrderFront: true)
            return
        }
        for (index, panel) in panels.enumerated() where screens.indices.contains(index) {
            if panel.frame != screens[index].frame {
                panel.setFrame(screens[index].frame, display: true)
            }
        }
        enforceShield(forceOrderFront: true)
    }

    private func enforceShield(forceOrderFront: Bool = false) {
        guard !isPasswordPromptActive else { return }
        attachToShieldSpace()
        let needsActivation = !NSApp.isActive
        let activeIndex = panels.indices.contains(scanController.activeScreenIndex) ? scanController.activeScreenIndex : 0
        let targetKeyPanel = panels.indices.contains(activeIndex) ? panels[activeIndex] : panels.first
        let needsKey = !(targetKeyPanel?.isKeyWindow ?? false)
        if needsActivation || forceOrderFront {
            NSApp.activate(ignoringOtherApps: true)
        }
        if NSApp.presentationOptions != Self.kioskPresentation {
            NSApp.presentationOptions = Self.kioskPresentation
        }
        for panel in panels {
            if panel.level != Self.shieldLevel {
                panel.level = Self.shieldLevel
            }
            if forceOrderFront || needsActivation || needsKey || !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
        if forceOrderFront || needsActivation || needsKey {
            targetKeyPanel?.makeKeyAndOrderFront(nil)
        }
    }

    /// Two fingers sideways on the trackpad open a settings drawer on the screen under the pointer.
    private func watchSwipes() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.track(event) }
            return event
        }
    }

    private func track(_ event: NSEvent) {
        // Trackpad gestures only: a mouse wheel has no phase, and momentum is the fingers already gone.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) {
            swipe = .initial
            isSwipeUsed = false
        }
        guard event.phase.contains(.changed), !isSwipeUsed else { return }
        let dx = SwipeTracker.fingerDelta(scrollDelta: event.scrollingDeltaX, isNatural: event.isDirectionInvertedFromDevice)
        swipe = swipe.adding(dx: dx, dy: event.scrollingDeltaY)
        guard let direction = swipe.direction,
              let index = panels.firstIndex(where: { $0 === event.window }) else { return }
        isSwipeUsed = true
        drawers[index].drawer = drawers[index].drawer.after(direction)
    }
}

/// Borderless panels refuse key status by default; the overlay needs it so the first click registers.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct KeyboardLockView: View {
    let lock: KeyboardLock
    let link: ScreenSaverLink
    let dimmer: ScreenSaverDimmer
    let drawer: DrawerState
    let sessions: ClaudeSessionMonitor?
    let display: NSScreen
    let screenIndex: Int
    let scanController: OwnerScanController
    let onUnlock: @MainActor () -> Void
    let onPasswordPrompt: @MainActor () -> Void

    var body: some View {
        switch lock.unlock {
        case .holdButton: cleaningLock
        case .ownerAuthentication: screenSaver
        }
    }

    /// Reads the settings live, so a change in a drawer shows at once.
    private var screenSaver: some View {
        let settings = link.settings
        return ZStack {
            // One mascot, on the first display, is enough company and saves drawing on every screen.
            ScreenSaverView(settings: settings, dimmer: dimmer, mascot: screenIndex == 0 ? settings.activeMascot : .none, display: display, onUpdate: link.update) {
                OwnerUnlockControls(screenIndex: screenIndex, scanController: scanController, onPasswordPrompt: onPasswordPrompt)
            } corner: {
                if settings.showsSessions, let sessions {
                    ClaudeSessionsOverlay(monitor: sessions, corner: settings.sessionsCorner, pinned: settings.pinnedSessionIDs,
                                          onPin: { id, isPinned in link.update { $0.pinning(id, isPinned) } })
                }
            }
            ScreenSaverDrawers(state: drawer, link: link, dimmer: dimmer)
        }
    }

    private var cleaningLock: some View {
        ZStack {
            Color.black
            VStack(spacing: 18) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Keyboard locked").font(.largeTitle.weight(.bold))
                Text("Wipe away — keys do nothing until you unlock.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TimedHoldButton(onUnlock: onUnlock)
                    .padding(.top, 8)
                TimelineView(.periodic(from: lock.lockedAt, by: 1)) { context in
                    Text("Unlocks by itself in \(Self.format(lock.remaining(at: context.date)))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The owner check: Touch ID inline, or the login password prompt when Touch ID is missing.
struct OwnerUnlockControls: View {
    let screenIndex: Int
    let scanController: OwnerScanController
    let onPasswordPrompt: @MainActor () -> Void

    var body: some View {
        if OwnerUnlockPath(hasBiometry: OwnerAuth.hasBiometry) == .inlineTouchID {
            OwnerScanView(controller: scanController, screenIndex: screenIndex)
        } else {
            OwnerUnlockButton(onTap: onPasswordPrompt)
        }
    }
}

/// Starts the owner check with the login password prompt.
private struct OwnerUnlockButton: View {
    let onTap: @MainActor () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Label("Unlock as owner", systemImage: "touchid")
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

/// Private SkyLight space positioned at `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock` (400),
/// placing our lock overlay strictly above macOS TCC "Allow" alerts (`UserNotificationCenter` at level 299),
/// screen lock (300), and security prompts (200), because WindowServer composites Spaces by absolute level
/// before comparing `NSWindow.level`.
private final class SkyLightShieldSpace {
    private typealias MainConnectionIDFn = @convention(c) () -> UInt32
    private typealias SpaceCreateFn = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroyFn = @convention(c) (UInt32, UInt64) -> Int32
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (UInt32, UInt64, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (UInt32, CFArray) -> Int32
    private typealias HideSpacesFn = @convention(c) (UInt32, CFArray) -> Int32
    private typealias AddWindowsToSpacesFn = @convention(c) (UInt32, CFArray, CFArray) -> Int32
    private typealias RemoveWindowsFromSpacesFn = @convention(c) (UInt32, CFArray, CFArray) -> Int32

    private static let shieldAbsoluteLevel: Int32 = 400
    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private let connectionID: UInt32
    private let spaceID: UInt64
    private let spaceArray: CFArray
    private let spaceDestroy: SpaceDestroyFn
    private let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevelFn
    private let showSpaces: ShowSpacesFn
    private let hideSpaces: HideSpacesFn
    private let addWindowsToSpaces: AddWindowsToSpacesFn
    private let removeWindowsFromSpaces: RemoveWindowsFromSpacesFn

    init?() {
        guard let handle = dlopen(Self.skyLightPath, RTLD_LAZY) else { return nil }
        guard let mainConnSym = dlsym(handle, "CGSMainConnectionID"),
              let createSym = dlsym(handle, "CGSSpaceCreate"),
              let destroySym = dlsym(handle, "CGSSpaceDestroy"),
              let levelSym = dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
              let showSym = dlsym(handle, "CGSShowSpaces"),
              let hideSym = dlsym(handle, "CGSHideSpaces"),
              let addSym = dlsym(handle, "CGSAddWindowsToSpaces"),
              let removeSym = dlsym(handle, "CGSRemoveWindowsFromSpaces") else {
            return nil
        }

        let mainConnectionID = unsafeBitCast(mainConnSym, to: MainConnectionIDFn.self)
        let spaceCreate = unsafeBitCast(createSym, to: SpaceCreateFn.self)
        self.spaceDestroy = unsafeBitCast(destroySym, to: SpaceDestroyFn.self)
        self.spaceSetAbsoluteLevel = unsafeBitCast(levelSym, to: SpaceSetAbsoluteLevelFn.self)
        self.showSpaces = unsafeBitCast(showSym, to: ShowSpacesFn.self)
        self.hideSpaces = unsafeBitCast(hideSym, to: HideSpacesFn.self)
        self.addWindowsToSpaces = unsafeBitCast(addSym, to: AddWindowsToSpacesFn.self)
        self.removeWindowsFromSpaces = unsafeBitCast(removeSym, to: RemoveWindowsFromSpacesFn.self)

        let cid = mainConnectionID()
        let sid = spaceCreate(cid, 1, nil)
        guard sid != 0 else { return nil }

        self.connectionID = cid
        self.spaceID = sid
        let spaces = [NSNumber(value: sid)] as CFArray
        self.spaceArray = spaces
        _ = self.spaceSetAbsoluteLevel(cid, sid, Self.shieldAbsoluteLevel)
        _ = self.showSpaces(cid, spaces)
    }

    func attach(windowNumbers: [Int]) {
        let validNumbers = windowNumbers.filter { $0 > 0 }.map { NSNumber(value: $0) }
        guard !validNumbers.isEmpty else { return }
        _ = spaceSetAbsoluteLevel(connectionID, spaceID, Self.shieldAbsoluteLevel)
        _ = showSpaces(connectionID, spaceArray)
        _ = addWindowsToSpaces(connectionID, validNumbers as CFArray, spaceArray)
    }

    func detach(windowNumbers: [Int]) {
        let validNumbers = windowNumbers.filter { $0 > 0 }.map { NSNumber(value: $0) }
        if !validNumbers.isEmpty {
            _ = removeWindowsFromSpaces(connectionID, validNumbers as CFArray, spaceArray)
        }
        _ = hideSpaces(connectionID, spaceArray)
    }

    func destroy(windowNumbers: [Int]) {
        detach(windowNumbers: windowNumbers)
        _ = spaceDestroy(connectionID, spaceID)
    }
}
