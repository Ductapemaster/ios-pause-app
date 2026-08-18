import Foundation

public enum AppRuleError: Error, Equatable, Sendable {
    case invalidSessionsPerDay
    case invalidSessionLengthMinutes
}

public struct AppRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var sessionsPerDay: Int
    public var sessionLengthMinutes: Int

    public init(id: UUID = UUID(), sessionsPerDay: Int, sessionLengthMinutes: Int) throws {
        guard sessionsPerDay >= 1 else {
            throw AppRuleError.invalidSessionsPerDay
        }
        guard sessionLengthMinutes >= 1 else {
            throw AppRuleError.invalidSessionLengthMinutes
        }

        self.id = id
        self.sessionsPerDay = sessionsPerDay
        self.sessionLengthMinutes = sessionLengthMinutes
    }
}
