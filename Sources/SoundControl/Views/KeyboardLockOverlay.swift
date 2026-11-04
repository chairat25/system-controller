import AppKit
import SwiftUI
import SoundControlCore

/// One dimmed panel per screen above everything (menu bar and Dock included), so stray trackpad
/// clicks while wiping land on the overlay instead of other apps.
@MainActor
final class KeyboardLockOverlay {
    private let panels: [NSPanel]

    init(lock: KeyboardLock,
         onUnlock: @escaping @MainActor () -> Void,
         onPasswordPrompt: @escaping @MainActor () -> Void) {
        panels = NSScreen.screens.enumerated().map { index, screen in
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: KeyboardLockView(lock: lock, onUnlock: onUnlock,
                                                                         onPasswordPrompt: onPasswordPrompt,
                                                                         hasScanner: index == 0))
            panel.setFrame(screen.frame, display: true)
            return panel
        }
        NSApp.activate()
        panels.forEach { $0.orderFrontRegardless() }
        panels.first?.makeKey()
    }

    func close() {
        panels.forEach { $0.close() }
    }
}

/// Borderless panels refuse key status by default; the overlay needs it so the first click registers.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct KeyboardLockView: View {
    let lock: KeyboardLock
    let onUnlock: @MainActor () -> Void
    let onPasswordPrompt: @MainActor () -> Void
    /// Only the main display runs the owner check, so one Touch ID prompt appears instead of one per screen.
    let hasScanner: Bool
    @State private var isScanning = false
    @State private var failure: String?

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 18) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Keyboard locked").font(.largeTitle.weight(.bold))
                Text(lock.unlock == .holdButton
                     ? "Wipe away — keys do nothing until you unlock."
                     : "Screen stays on. Only the owner can unlock.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                unlockControls
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { autoStartOwnerScan() }
    }

    @ViewBuilder
    private var unlockControls: some View {
        switch lock.unlock {
        case .holdButton:
            HoldToUnlockButton(onUnlock: onUnlock)
                .padding(.top, 8)
            TimelineView(.periodic(from: lock.lockedAt, by: 1)) { context in
                Text("Unlocks by itself in \(Self.format(lock.remaining(at: context.date)))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .ownerAuthentication:
            ownerControls
        }
    }

    @ViewBuilder
    private var ownerControls: some View {
        if !hasScanner {
            Text("Unlock on the main display").font(.callout).foregroundStyle(.secondary)
        } else if isScanning {
            TouchIDScanner(onOutcome: finishScan, onPasswordPrompt: onPasswordPrompt)
                .padding(.top, 8)
        } else {
            OwnerUnlockButton(onTap: startOwnerUnlock)
                .padding(.top, 8)
        }
        if let failure {
            Text(failure).font(.callout).foregroundStyle(Theme.warning)
        }
    }

    private var ownerPath: OwnerUnlockPath { OwnerUnlockPath(hasBiometry: OwnerAuth.hasBiometry) }

    /// The Touch ID check starts as soon as the owner lock appears, so placing a finger is the only step.
    private func autoStartOwnerScan() {
        guard hasScanner, lock.unlock == .ownerAuthentication, ownerPath == .inlineTouchID else { return }
        isScanning = true
    }

    /// Touch ID shows inline; without it the system password prompt opens and the keyboard passes through.
    private func startOwnerUnlock() {
        guard ownerPath == .inlineTouchID else {
            onPasswordPrompt()
            return
        }
        failure = nil
        isScanning = true
    }

    private func finishScan(_ outcome: OwnerAuth.Outcome) {
        isScanning = false
        switch outcome {
        case .unlocked: onUnlock()
        case .cancelled: break
        case .failed(let message): failure = message
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// Starts the owner check: Touch ID inline, or the login password prompt when Touch ID is missing.
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

/// Needs a press of `KeyboardLock.holdToUnlock`, so a palm brushing the trackpad does not unlock.
private struct HoldToUnlockButton: View {
    let onUnlock: @MainActor () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Text("Hold to unlock")
            .font(.headline)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Theme.accent).frame(width: proxy.size.width * progress)
                    }
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: KeyboardLock.holdToUnlock, maximumDistance: 40) {
                onUnlock()
            } onPressingChanged: { isPressing in
                withAnimation(isPressing ? .linear(duration: KeyboardLock.holdToUnlock) : .easeOut(duration: 0.2)) {
                    progress = isPressing ? 1 : 0
                }
            }
    }
}
