import AppKit
import Combine
import LocalAuthentication

enum AuthOutcome {
    case success
    case cancelled
    case failed
}

/// Wraps LocalAuthentication so the lock screen can offer the Touch ID / Face ID
/// equivalent of the iPhone's biometric button.
final class AuthManager: ObservableObject {

    @Published private(set) var biometricsAvailable = false
    @Published private(set) var biometryLabel = "Touch ID"

    init() {
        refresh()
    }

    /// Re-reads biometric capability. Called whenever a lock screen appears and
    /// on wake, since the sensor can come and go.
    func refresh() {
        let context = LAContext()
        var error: NSError?
        biometricsAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        biometryLabel = label(for: context.biometryType)
    }

    func authenticate(reason: String) async -> AuthOutcome {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.localizedCancelTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .failed
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else if let laError = error as? LAError,
                          [.userCancel, .systemCancel, .appCancel].contains(laError.code) {
                    continuation.resume(returning: .cancelled)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }

    private func label(for type: LABiometryType) -> String {
        switch type {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        default:
            if #available(macOS 14.0, *), type == .opticID { return "Optic ID" }
            return "Biometrics"
        }
    }
}
