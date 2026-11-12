import AppKit
import Observation
import SoundControlCore

/// Locks the keyboard while the screen stays on: blocks keys and covers every screen with an overlay.
/// The overlay opens either by holding its button (`holdButton`) or by the owner's Touch ID / password.
/// The owner lock doubles as the Smartheart Screen Saver.
@MainActor
@Observable
final class KeyboardLockController {
    private(set) var lock: KeyboardLock?
    /// Why the last lock attempt failed, shown under the lock buttons.
    private(set) var problem: String?

    @ObservationIgnored private let blocker = KeyboardBlocker()
    @ObservationIgnored private var overlay: KeyboardLockOverlay?
    @ObservationIgnored private var expiry: DispatchWorkItem?
    @ObservationIgnored private var isAuthenticating = false

    var isLocked: Bool { lock != nil }

    func lockKeyboard() {
        startLock(.holdButton, screenSaver: .default, sessions: nil, onPin: { _, _ in })
    }

    func lockForOwner(screenSaver: ScreenSaverSettings, sessions: ClaudeSessionMonitor,
                      onPin: @escaping @MainActor (String, Bool) -> Void) {
        guard OwnerAuth.isAvailable else {
            problem = OwnerAuth.setupMessage
            return
        }
        startLock(.ownerAuthentication, screenSaver: screenSaver, sessions: sessions, onPin: onPin)
    }

    func unlockKeyboard() {
        expiry?.cancel()
        expiry = nil
        blocker.stop()
        overlay?.close()
        overlay = nil
        lock = nil
        // Full-screen views on every display leave a lot of freed heap behind; give those pages back now.
        DispatchQueue.main.async { malloc_zone_pressure_relief(nil, 0) }
    }

    private func startLock(_ unlock: UnlockMethod, screenSaver: ScreenSaverSettings, sessions: ClaudeSessionMonitor?,
                           onPin: @escaping @MainActor (String, Bool) -> Void) {
        guard lock == nil else { return }
        guard KeyboardBlocker.hasPermission else {
            KeyboardBlocker.requestPermission()
            problem = KeyboardBlocker.permissionMessage
            return
        }
        guard blocker.start() else {
            problem = KeyboardBlocker.permissionMessage
            return
        }
        let next = KeyboardLock(lockedAt: Date(), unlock: unlock)
        problem = nil
        lock = next
        overlay = KeyboardLockOverlay(lock: next, screenSaver: screenSaver, sessions: sessions, onPin: onPin, onUnlock: { [weak self] in self?.unlockKeyboard() },
                                      onPasswordPrompt: { [weak self] in Task { await self?.unlockWithPassword() } })
        if next.expires { scheduleExpiry() }
    }

    /// Keys pass through only while the system password prompt needs them. Touch ID runs inline and needs none.
    private func unlockWithPassword() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        blocker.passesKeys = true
        let outcome = await OwnerAuth.authenticate()
        blocker.passesKeys = false
        isAuthenticating = false
        switch outcome {
        case .unlocked: unlockKeyboard()
        case .cancelled: break
        case .failed(let message): problem = message
        }
    }

    /// Safety net: a hold lock comes back by itself even if the mouse stops working.
    private func scheduleExpiry() {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.unlockKeyboard() }
        }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardLock.maxDuration, execute: work)
    }
}
