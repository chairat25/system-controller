import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import Observation
import SwiftUI
import SoundControlCore

/// Coordinates inline Touch ID scanning across all displays while locked so the active key window
/// always owns an unoccluded `LAAuthenticationView`, even when an external display is connected or focused.
@MainActor
@Observable
final class OwnerScanController {
    private(set) var isMatched = false
    private(set) var isHolding = false
    /// The gauge is full after a match: the capsule says so before the overlay goes away.
    private(set) var isWelcomed = false
    private(set) var isPaused = false
    private(set) var failure: String?
    /// Mounted before the read starts so its inline `LAAuthenticationView` is on screen (no system alert).
    /// A context cannot be reused once invalidated, so every restart arms a new one.
    private(set) var laContext = LAContext()
    private(set) var activeScreenIndex: Int

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var isSensorReady = false
    @ObservationIgnored private let onUnlock: @MainActor () -> Void
    @ObservationIgnored private let onPasswordPrompt: @MainActor () -> Void

    init(activeScreenIndex: Int = 0,
         onUnlock: @escaping @MainActor () -> Void,
         onPasswordPrompt: @escaping @MainActor () -> Void) {
        self.activeScreenIndex = activeScreenIndex
        self.onUnlock = onUnlock
        self.onPasswordPrompt = onPasswordPrompt
    }

    func setHolding(_ holding: Bool) {
        if isHolding != holding { isHolding = holding }
    }

    func sensorDidMoveToWindow(forScreen index: Int) {
        guard index == activeScreenIndex else { return }
        isSensorReady = true
        if !isPaused, scanTask == nil, !isMatched {
            startScan()
        }
    }

    func setActiveScreen(_ index: Int) {
        guard index != activeScreenIndex, !isMatched else { return }
        scanTask?.cancel()
        scanTask = nil
        isSensorReady = false
        laContext.invalidate()
        activeScreenIndex = index
        laContext = LAContext()
    }

    func rearmForScreenChange(activeScreenIndex index: Int) {
        guard !isMatched else { return }
        scanTask?.cancel()
        scanTask = nil
        isSensorReady = false
        laContext.invalidate()
        activeScreenIndex = index
        laContext = LAContext()
    }

    func startScan() {
        guard isSensorReady, scanTask == nil, !isMatched else { return }
        isPaused = false
        failure = nil
        let context = laContext
        scanTask = Task { [weak self] in
            let outcome = await OwnerAuth.authenticateBiometrics(with: context)
            await self?.finishScan(outcome, from: context)
        }
    }

    /// The system password prompt runs its own check, so the inline read pauses until the owner resumes it.
    func usePassword() {
        stopScan()
        isPaused = true
        onPasswordPrompt()
    }

    func resumeAfterPasswordCancel() {
        guard isPaused, !isMatched else { return }
        isPaused = false
        rearm(after: 0.2)
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isSensorReady = false
        laContext.invalidate()
        laContext = LAContext()
    }

    /// Ignores results of a read that was already replaced or stopped.
    private func finishScan(_ outcome: OwnerAuth.Outcome, from context: LAContext) async {
        guard context === laContext else { return }
        scanTask = nil
        switch outcome {
        case .unlocked:
            isMatched = true
            try? await Task.sleep(for: .seconds(Timing.matchFill))
            guard !Task.isCancelled else { return }
            isWelcomed = true
            try? await Task.sleep(for: .seconds(Timing.welcomeHold))
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
        isSensorReady = false
        laContext.invalidate()
        laContext = LAContext()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.clearScanTaskAndStart()
        }
    }

    private func clearScanTaskAndStart() {
        scanTask = nil
        startScan()
    }

    private enum Timing {
        /// Slow enough to see the gauge fill after a quick touch that matched.
        static let matchFill: TimeInterval = 0.9
        static let retryDelay: TimeInterval = 1
        /// How long "Welcome back" stays before the screen saver closes.
        static let welcomeHold: TimeInterval = 0.9
    }
}

/// Owner lock: Touch ID reads inline on whichever screen currently owns focus, while every display shows
/// the same unlock gauge and password fallback. Resting a finger unlocks without needing to hunt for
/// the primary display when an external monitor is connected.
struct OwnerScanView: View {
    let controller: OwnerScanController
    let screenIndex: Int

    var body: some View {
        VStack(spacing: 14) {
            // LAAuthenticationView must remain unoccluded and opaque in the key window, otherwise
            // NSOcclusionDetectionView pauses Touch ID evaluation on external/secondary display setups.
            ZStack {
                if screenIndex == controller.activeScreenIndex {
                    TouchIDSensor(laContext: controller.laContext) {
                        controller.sensorDidMoveToWindow(forScreen: screenIndex)
                    }
                    .id(ObjectIdentifier(controller.laContext))
                    .frame(width: Layout.sensorSize, height: Layout.sensorSize)
                } else {
                    Image(systemName: "touchid")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.sensorSize, height: Layout.sensorSize)
                }
            }
            GaugeCapsule(title: controller.isWelcomed ? "Welcome back" : "Hold to unlock",
                         isFilled: controller.isMatched || controller.isHolding,
                         fillDuration: controller.isMatched ? Timing.matchFill : KeyboardLock.holdToUnlock,
                         showsTitle: controller.isWelcomed) {
                if controller.isWelcomed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: Timing.welcomeFade), value: controller.isWelcomed)
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40) {
            } onPressingChanged: { isPressing in
                controller.setHolding(isPressing)
            }
            if !controller.isPaused && controller.failure == nil {
                Text("Keep your finger on Touch ID").font(.callout).foregroundStyle(.secondary)
            }
            if let failure = controller.failure {
                Text(failure).font(.callout).foregroundStyle(Theme.warning)
            }
            if controller.isPaused {
                Button("Scan finger", action: controller.startScan).buttonStyle(.plain).font(.callout)
            } else {
                Button("Use password", action: controller.usePassword)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private enum Layout {
        static let sensorSize: CGFloat = 28
    }

    private enum Timing {
        static let matchFill: TimeInterval = 0.9
        static let welcomeFade: TimeInterval = 0.3
    }
}

/// Hosts the AppKit `LAAuthenticationView`, which shows the Touch ID icon for the given context and keeps
/// the check inline instead of in a system alert.
private struct TouchIDSensor: NSViewRepresentable {
    let laContext: LAContext
    let onWindowReady: @MainActor () -> Void

    func makeNSView(context: Context) -> SensorHostView {
        let host = SensorHostView()
        host.onWindowReady = onWindowReady
        let sensor = LAAuthenticationView(context: laContext, controlSize: .small)
        sensor.autoresizingMask = [.width, .height]
        sensor.frame = host.bounds
        host.addSubview(sensor)
        return host
    }

    func updateNSView(_ view: SensorHostView, context: Context) {
        view.onWindowReady = onWindowReady
    }
}

private final class SensorHostView: NSView {
    var onWindowReady: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let callback = onWindowReady
        DispatchQueue.main.async {
            MainActor.assumeIsolated { callback?() }
        }
    }
}
