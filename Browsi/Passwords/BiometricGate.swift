import Foundation
import LocalAuthentication

/// Touch ID / password gate in front of revealing or filling secrets.
/// A successful unlock is reused for a short grace period.
final class BiometricGate {
    static let shared = BiometricGate()
    var gracePeriod: TimeInterval { TimeInterval(Preferences.shared.authGracePeriod) }
    private var unlockedAt: Date?

    /// - Parameter force: always prompt, ignoring the "require authentication to fill" preference.
    func authenticate(reason: String, force: Bool = true) async -> Bool {
        if !force && !Preferences.shared.requireAuthToFill { return true }
        if let t = unlockedAt, Date.now.timeIntervalSince(t) < gracePeriod { return true }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { unlockedAt = .now }
            return ok
        } catch {
            return false
        }
    }

    func lock() { unlockedAt = nil }
}
