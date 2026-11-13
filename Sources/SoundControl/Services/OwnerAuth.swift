import LocalAuthentication

/// Owner check for the keyboard lock: Touch ID, or the login password when Touch ID is missing or fails.
/// Anyone at the Mac can see the prompt, but only the owner's finger or password gets through.
enum OwnerAuth {
    enum Outcome: Equatable {
        case unlocked
        case cancelled
        case failed(String)
    }

    static let setupMessage = "Owner lock needs a login password. Set one in System Settings → Touch ID & Password, then try again."

    /// False when the Mac has no login password, since the owner could never unlock.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// True when Touch ID can check the owner inline, so the system password alert is not needed.
    static var hasBiometry: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Pass the context that an inline `LAAuthenticationView` is attached to, so the check shows in the overlay.
    static func authenticate(with context: LAContext = LAContext()) async -> Outcome {
        await evaluate(.deviceOwnerAuthentication, with: context)
    }

    /// Touch ID only, never falling back to a macOS password dialog while the screen saver is up.
    static func authenticateBiometrics(with context: LAContext) async -> Outcome {
        await evaluate(.deviceOwnerAuthenticationWithBiometrics, with: context)
    }

    private static func evaluate(_ policy: LAPolicy, with context: LAContext) async -> Outcome {
        do {
            _ = try await context.evaluatePolicy(policy, localizedReason: "unlock the keyboard")
            return .unlocked
        } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
