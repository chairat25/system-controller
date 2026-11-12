import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI
import SoundControlCore

/// Owner lock: Touch ID is already reading when the overlay opens, so resting the owner's finger on the
/// sensor unlocks. Holding the button fills the gauge as a visual guide while the finger reads; only a
/// fingerprint match unlocks, and then the gauge finishes quickly. Letting go early empties the gauge.
/// A wrong finger shows a message and the reader re-arms.
struct OwnerScanView: View {
    let onUnlock: @MainActor () -> Void
    let onPasswordPrompt: @MainActor () -> Void
    @State private var isMatched = false
    @State private var isHolding = false
    @State private var isPaused = false
    @State private var failure: String?
    /// Mounted before the read starts so its inline `LAAuthenticationView` is on screen (no system alert).
    /// A context cannot be reused once invalidated, so every restart arms a new one.
    @State private var laContext = LAContext()
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 14) {
            GaugeCapsule(title: isMatched ? "Unlocking" : "Hold to unlock",
                         isFilled: isMatched || isHolding,
                         fillDuration: isMatched ? Timing.matchFill : KeyboardLock.holdToUnlock) {
                TouchIDSensor(laContext: laContext)
                    .id(ObjectIdentifier(laContext))
                    .frame(width: Layout.sensorSize, height: Layout.sensorSize)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40) {
            } onPressingChanged: { isPressing in
                isHolding = isPressing
            }
            if !isPaused && failure == nil {
                Text("Keep your finger on Touch ID").font(.callout).foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(.callout).foregroundStyle(Theme.warning)
            }
            if isPaused {
                Button("Scan finger", action: startScan).buttonStyle(.plain).font(.callout)
            } else {
                Button("Use password", action: usePassword)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: startScan)
        .onDisappear(perform: stopScan)
    }

    private func startScan() {
        isPaused = false
        let context = laContext
        scanTask = Task {
            let outcome = await OwnerAuth.authenticate(with: context)
            await finishScan(outcome, from: context)
        }
    }

    /// Ignores results of a read that was already replaced or stopped.
    private func finishScan(_ outcome: OwnerAuth.Outcome, from context: LAContext) async {
        guard context === laContext else { return }
        switch outcome {
        case .unlocked:
            isMatched = true
            try? await Task.sleep(for: .seconds(Timing.matchFill))
            guard !Task.isCancelled else { return }
            onUnlock()
        case .cancelled:
            rearm(after: Timing.retryDelay)
        case .failed(let message):
            failure = message
            rearm(after: Timing.retryDelay)
        }
    }

    /// The delay keeps an immediate, repeating failure (such as a Touch ID lockout) from spinning.
    private func rearm(after delay: TimeInterval) {
        laContext = LAContext()
        scanTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            startScan()
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        laContext.invalidate()
        laContext = LAContext()
    }

    /// The system password prompt runs its own check, so the inline read pauses until the owner resumes it.
    private func usePassword() {
        stopScan()
        isPaused = true
        onPasswordPrompt()
    }

    private enum Layout {
        static let sensorSize: CGFloat = 28
    }

    private enum Timing {
        static let matchFill: TimeInterval = 0.3
        static let retryDelay: TimeInterval = 1
    }
}

/// Hosts the AppKit `LAAuthenticationView`, which shows the Touch ID icon for the given context and keeps
/// the check inline instead of in a system alert.
private struct TouchIDSensor: NSViewRepresentable {
    let laContext: LAContext

    func makeNSView(context: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: laContext, controlSize: .small)
    }

    func updateNSView(_ view: LAAuthenticationView, context: Context) {}
}
