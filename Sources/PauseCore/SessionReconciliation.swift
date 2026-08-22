import Foundation

public enum SessionReconciliation: Equatable, Sendable {
    case keepOpen
    case activateProvisional
    case expire
    case noSession
}

public func reconciliation(for runtime: RuleRuntime, now: Date) -> SessionReconciliation {
    guard let session = runtime.openSession else { return .noSession }
    guard session.expiresAt > now else { return .expire }
    return session.state == .provisional ? .activateProvisional : .keepOpen
}
