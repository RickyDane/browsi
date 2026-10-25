import Foundation
import LocalAuthentication

/// Touch ID / password gate in front of revealing or filling secrets.
/// A successful unlock is reused for a short grace period.
final class BiometricGate {
    static let shared = BiometricGate()
    var gracePeriod: TimeInterval = 300
    private var unlockedAt: Date?

    func authenticate(reason: String) async -> Bool {
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
