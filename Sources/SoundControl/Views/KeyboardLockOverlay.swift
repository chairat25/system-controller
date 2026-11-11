import AppKit
import SwiftUI
import SoundControlCore

/// One dimmed panel per screen above everything (menu bar and Dock included), so stray trackpad
/// clicks while wiping land on the overlay instead of other apps.
/// The owner lock shows the Smartheart Screen Saver on every screen; the cleaning lock shows a plain lock screen.
@MainActor
final class KeyboardLockOverlay {
    private let panels: [NSPanel]
    private let dimmer: ScreenSaverDimmer

    init(lock: KeyboardLock,
         screenSaver: ScreenSaverSettings,
         sessions: ClaudeSessionMonitor?,
         onPin: @escaping @MainActor (String, Bool) -> Void,
         onUnlock: @escaping @MainActor () -> Void,
         onPasswordPrompt: @escaping @MainActor () -> Void) {
        let dimmer = ScreenSaverDimmer(settings: screenSaver)
        self.dimmer = dimmer
        panels = NSScreen.screens.enumerated().map { index, screen in
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: KeyboardLockView(lock: lock, settings: screenSaver,
                                                                         dimmer: dimmer, sessions: sessions, onPin: onPin,
                                                                         onUnlock: onUnlock,
                                                                         onPasswordPrompt: onPasswordPrompt,
                                                                         hasScanner: index == 0))
            panel.setFrame(screen.frame, display: true)
            return panel
        }
        NSApp.activate()
        panels.forEach { $0.orderFrontRegardless() }
        panels.first?.makeKey()
        if lock.unlock == .ownerAuthentication { dimmer.start() }
    }

    func close() {
        dimmer.stop()
        panels.forEach { $0.close() }
    }
}

/// Borderless panels refuse key status by default; the overlay needs it so the first click registers.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct KeyboardLockView: View {
    let lock: KeyboardLock
    let settings: ScreenSaverSettings
    let dimmer: ScreenSaverDimmer
    let sessions: ClaudeSessionMonitor?
    let onPin: @MainActor (String, Bool) -> Void
    let onUnlock: @MainActor () -> Void
    let onPasswordPrompt: @MainActor () -> Void
    /// Only the main display runs the owner check, so one Touch ID prompt appears instead of one per screen.
    let hasScanner: Bool

    var body: some View {
        switch lock.unlock {
        case .holdButton: cleaningLock
        case .ownerAuthentication:
            ScreenSaverView(settings: settings, dimmer: dimmer) {
                OwnerUnlockControls(hasScanner: hasScanner, onUnlock: onUnlock, onPasswordPrompt: onPasswordPrompt)
            } corner: {
                if settings.showsSessions, let sessions {
                    ClaudeSessionsOverlay(monitor: sessions, corner: settings.sessionsCorner, pinned: settings.pinnedSessionIDs, onPin: onPin)
                }
            }
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
    let hasScanner: Bool
    let onUnlock: @MainActor () -> Void
    let onPasswordPrompt: @MainActor () -> Void

    var body: some View {
        if !hasScanner {
            Text("Unlock on the main display").font(.callout).foregroundStyle(.secondary)
        } else if OwnerUnlockPath(hasBiometry: OwnerAuth.hasBiometry) == .inlineTouchID {
            OwnerScanView(onUnlock: onUnlock, onPasswordPrompt: onPasswordPrompt)
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
