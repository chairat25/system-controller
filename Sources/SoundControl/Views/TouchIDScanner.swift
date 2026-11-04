import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

/// Touch ID check drawn inside the overlay instead of the system alert. The system draws the sensor icon,
/// and a ring spins around it while the finger is read.
struct TouchIDScanner: View {
    let onOutcome: @MainActor (OwnerAuth.Outcome) -> Void
    let onPasswordPrompt: @MainActor () -> Void
    @State private var laContext = LAContext()
    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .trim(from: 0, to: ScannerLayout.arcLength)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: ScannerLayout.ringWidth, lineCap: .round))
                    .frame(width: ScannerLayout.size, height: ScannerLayout.size)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(.linear(duration: ScannerLayout.spinDuration).repeatForever(autoreverses: false),
                               value: isSpinning)
                TouchIDSensor(laContext: laContext)
                    .frame(width: ScannerLayout.sensorSize, height: ScannerLayout.sensorSize)
            }
            .frame(width: ScannerLayout.size, height: ScannerLayout.size)
            Text("Place your finger on Touch ID").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("Use password", action: usePassword)
                Button("Cancel", action: cancel)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .onAppear { isSpinning = true }
        .task {
            onOutcome(await OwnerAuth.authenticate(with: laContext))
        }
    }

    /// Invalidating makes the pending `evaluatePolicy` fail with `appCancel`, which reports `.cancelled`.
    private func cancel() {
        laContext.invalidate()
    }

    private func usePassword() {
        laContext.invalidate()
        onPasswordPrompt()
    }
}

private enum ScannerLayout {
    static let size: CGFloat = 96
    static let sensorSize: CGFloat = 64
    static let ringWidth: CGFloat = 3
    /// Share of the ring drawn as a moving arc.
    static let arcLength: CGFloat = 0.3
    static let spinDuration: TimeInterval = 1.2
}

/// Hosts the AppKit `LAAuthenticationView`, which shows the Touch ID icon for the given context.
private struct TouchIDSensor: NSViewRepresentable {
    let laContext: LAContext

    func makeNSView(context: Context) -> LAAuthenticationView {
        LAAuthenticationView(context: laContext, controlSize: .large)
    }

    func updateNSView(_ view: LAAuthenticationView, context: Context) {}
}
