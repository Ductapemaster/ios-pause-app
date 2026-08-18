import Foundation

public enum RefusalReason: Equatable, Sendable {
    case dailyAllowanceExhausted(limit: Int)
    case sessionAlreadyOpen(until: Date)
}

public enum SessionDecision: Equatable, Sendable {
    case allowed(sessionNumber: Int, lengthMinutes: Int)
    case refused(RefusalReason)
}
