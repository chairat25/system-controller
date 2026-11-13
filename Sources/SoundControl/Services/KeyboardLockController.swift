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
    @ObservationIgnored var onUnlock: (@MainActor () -> Void)?

    var isLocked: Bool { lock != nil }

    func lockKeyboard() {
        startLock(.holdButton, link: .fixed(.default), sessions: nil)
    }

    func lockForOwner(link: ScreenSaverLink, sessions: ClaudeSessionMonitor) {
        guard OwnerAuth.isAvailable else {
            problem = OwnerAuth.setupMessage
            return
        }
        startLock(.ownerAuthentication, link: link, sessions: sessions)
    }

    func unlockKeyboard() {
        expiry?.cancel()
        expiry = nil
        blocker.stop()
        overlay?.close()
        overlay = nil
        lock = nil
        onUnlock?()
        // Full-screen views on every display leave a lot of freed heap behind; give those pages back now.
        DispatchQueue.main.async { malloc_zone_pressure_relief(nil, 0) }
    }

    private func startLock(_ unlock: UnlockMethod, link: ScreenSaverLink, sessions: ClaudeSessionMonitor?) {
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
        overlay = KeyboardLockOverlay(lock: next, link: link, sessions: sessions, onUnlock: { [weak self] in self?.unlockKeyboard() },
                                      onPasswordPrompt: { [weak self] in Task { await self?.unlockWithPassword() } })
        if next.expires { scheduleExpiry() }
    }

    /// Keys pass through only while the system password prompt needs them. Touch ID runs inline and needs none.
    private func unlockWithPassword() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        overlay?.setPasswordPromptActive(true)
        blocker.passesKeys = true
        let outcome = await OwnerAuth.authenticate()
        blocker.passesKeys = false
        isAuthenticating = false
        switch outcome {
        case .unlocked:
            unlockKeyboard()
        case .cancelled:
            overlay?.setPasswordPromptActive(false)
        case .failed(let message):
            overlay?.setPasswordPromptActive(false)
            problem = message
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
