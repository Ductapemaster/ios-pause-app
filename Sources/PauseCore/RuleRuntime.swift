import Foundation

public enum OpenSessionState: String, Codable, Equatable, Sendable {
    case provisional
    case active
}

public struct OpenSession: Codable, Equatable, Sendable {
    public let activityName: String
    public let expiresAt: Date
    public var state: OpenSessionState

    public init(activityName: String, expiresAt: Date, state: OpenSessionState) {
        self.activityName = activityName
        self.expiresAt = expiresAt
        self.state = state
    }
}

public enum RuleRuntimeError: Error, Equatable, Sendable {
    case sessionAlreadyOpen
    case noOpenSession
    case noProvisionalSession
    case activeSessionCannotRollback
}

public struct RuleRuntime: Codable, Equatable, Sendable {
    public var logicalDay: CalendarDay
    public var sessionsStarted: Int
    public var openSession: OpenSession?
    /// When the last session ended, which is what a cooldown is measured from.
    /// Absent until a session has expired.
    public var lastSessionExpiry: Date?

    public init(
        logicalDay: CalendarDay,
        sessionsStarted: Int,
        openSession: OpenSession? = nil,
        lastSessionExpiry: Date? = nil
    ) {
        self.logicalDay = logicalDay
        self.sessionsStarted = sessionsStarted
        self.openSession = openSession
        self.lastSessionExpiry = lastSessionExpiry
    }

    public mutating func rollOver(to day: CalendarDay) {
        guard logicalDay != day else { return }
        logicalDay = day
        sessionsStarted = 0
    }

    public mutating func reserve(activityName: String, expiresAt: Date) throws {
        guard openSession == nil else {
            throw RuleRuntimeError.sessionAlreadyOpen
        }

        sessionsStarted += 1
        openSession = OpenSession(activityName: activityName, expiresAt: expiresAt, state: .provisional)
    }

    public mutating func activateReservedSession() throws {
        guard openSession != nil else {
            throw RuleRuntimeError.noOpenSession
        }
        guard openSession?.state == .provisional else {
            throw RuleRuntimeError.noProvisionalSession
        }

        openSession?.state = .active
    }

    public mutating func rollBackReservedSession() throws {
        guard let openSession else {
            throw RuleRuntimeError.noOpenSession
        }
        guard openSession.state == .provisional else {
            throw RuleRuntimeError.activeSessionCannotRollback
        }

        self.openSession = nil
        sessionsStarted = max(0, sessionsStarted - 1)
    }

    /// Stamps the session's own stored expiry rather than the current instant.
    /// The monitor's callback can arrive late, or be missed and repaired at the
    /// app's next launch; anchoring to `expiresAt` keeps a cooldown from being
    /// extended by however long the repair took.
    public mutating func clearExpiredSession(at now: Date) {
        guard let openSession, openSession.expiresAt <= now else { return }
        lastSessionExpiry = openSession.expiresAt
        self.openSession = nil
    }
}
