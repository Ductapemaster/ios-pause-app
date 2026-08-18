import Foundation

public enum PauseCountdownError: Error, Equatable, Sendable {
    case nonpositiveDuration
}

public struct PauseCountdown: Equatable, Sendable {
    public let ruleID: UUID
    public let startedAt: Date
    public let endsAt: Date

    public init(ruleID: UUID, seconds: Int, now: Date) throws {
        guard seconds > 0 else {
            throw PauseCountdownError.nonpositiveDuration
        }

        self.ruleID = ruleID
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(seconds))
    }

    public func remainingSeconds(at now: Date) -> Int {
        max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    public func isComplete(at now: Date) -> Bool {
        now >= endsAt
    }
}

public struct PauseEntryDetails: Equatable, Sendable {
    public let ruleID: UUID
    public let sessionNumber: Int
    public let sessionsPerDay: Int
    public let lengthMinutes: Int
    public let pauseSeconds: Int

    public init(
        ruleID: UUID,
        sessionNumber: Int,
        sessionsPerDay: Int,
        lengthMinutes: Int,
        pauseSeconds: Int
    ) {
        self.ruleID = ruleID
        self.sessionNumber = sessionNumber
        self.sessionsPerDay = sessionsPerDay
        self.lengthMinutes = lengthMinutes
        self.pauseSeconds = pauseSeconds
    }
}

public enum PauseEntryResolution: Equatable, Sendable {
    case invalid
    case resolved(
        ruleID: UUID,
        sessionsPerDay: Int,
        pauseSeconds: Int,
        decision: SessionDecision
    )
}

public enum PauseEntryInput: Equatable, Sendable {
    case noIntent
    case intent(createdAt: Date, resolution: PauseEntryResolution)
}

public enum PauseEntryRoute: Equatable, Sendable {
    case configuration
    case repair
    case pause(PauseEntryDetails)
    case refused(RefusalReason)
}

public enum PauseEntryRouter {
    public static let maximumIntentAge: TimeInterval = 30

    public static func route(input: PauseEntryInput, now: Date) -> PauseEntryRoute {
        guard case let .intent(createdAt, resolution) = input else {
            return .configuration
        }

        let age = now.timeIntervalSince(createdAt)
        guard age >= 0, age <= maximumIntentAge else {
            return .repair
        }
        guard case let .resolved(ruleID, sessionsPerDay, pauseSeconds, decision) = resolution else {
            return .repair
        }

        switch decision {
        case let .allowed(sessionNumber, lengthMinutes):
            return .pause(
                PauseEntryDetails(
                    ruleID: ruleID,
                    sessionNumber: sessionNumber,
                    sessionsPerDay: sessionsPerDay,
                    lengthMinutes: lengthMinutes,
                    pauseSeconds: pauseSeconds
                )
            )
        case let .refused(reason):
            return .refused(reason)
        }
    }
}

public enum ForegroundPauseEvent: Equatable, Sendable {
    case sceneBecameInactive
}

public enum ForegroundPauseState: Equatable, Sendable {
    case configuration
    case countingDown
    case grantStarted

    public func transitioned(for event: ForegroundPauseEvent) -> ForegroundPauseState {
        switch (self, event) {
        case (.countingDown, .sceneBecameInactive):
            .configuration
        case (.configuration, .sceneBecameInactive), (.grantStarted, .sceneBecameInactive):
            self
        }
    }
}
