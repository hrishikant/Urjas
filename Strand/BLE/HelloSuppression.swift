import Foundation
import WhoopProtocol

/// Upstream's unanswered-handshake fallback, separate from the existing explicit-auth-refusal pause.
enum HelloSuppression {
    static let threshold = 3

    static func shouldSend(suppressed: Bool, userInitiated: Bool) -> Bool {
        !suppressed || userInitiated
    }

    static func countsAsUnanswered(pending: Bool, bonded: Bool,
                                   intentional: Bool, family: DeviceFamily) -> Bool {
        pending && !bonded && !intentional && family == .whoop5
    }

    static func key(_ id: UUID) -> String {
        "noop.helloUnanswered.\(id.uuidString.lowercased())"
    }

    static func suppressed(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    static func clear(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }

    static func keepAliveMayRun(connected: Bool, didBond: Bool, bonded: Bool,
                                family: DeviceFamily) -> Bool {
        connected && (didBond || (bonded && family == .whoop5))
    }
}
