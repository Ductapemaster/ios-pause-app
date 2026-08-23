import Foundation

public enum AppRuleError: Error, Equatable, Sendable {
    case invalidSessionsPerDay
    case invalidSessionLengthMinutes
}

/// The allowance bounds every entry point enforces, and the values a newly
/// covered app starts from.
///
/// `AppRule.init` stays deliberately looser than these — it rejects only values
/// below one, so a document written by an older build still decodes. These are
/// the bounds the user is held to at the points where a value is chosen.
public enum AppRuleLimits {
    public static let sessionsPerDay = 1...20
    public static let sessionLengthMinutes = 1...120

    public static let defaultSessionsPerDay = 3
    public static let defaultSessionLengthMinutes = 5
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

extension AppRule {
    /// The pair of values a rule is created from, carried from wherever the
    /// user chooses them to the save that writes the rule.
    public struct Allowance: Equatable, Sendable {
        public var sessionsPerDay: Int
        public var sessionLengthMinutes: Int

        public init(sessionsPerDay: Int, sessionLengthMinutes: Int) {
            self.sessionsPerDay = sessionsPerDay
            self.sessionLengthMinutes = sessionLengthMinutes
        }

        public static let `default` = Allowance(
            sessionsPerDay: AppRuleLimits.defaultSessionsPerDay,
            sessionLengthMinutes: AppRuleLimits.defaultSessionLengthMinutes
        )
    }
}
