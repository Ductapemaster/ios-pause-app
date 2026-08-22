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

public enum ConfigurationLoadState: Equatable, Sendable {
    case missing
    case knownGood
    case failed
}

public enum ConfigurationMutation: Equatable, Sendable {
    case pickerSelection
    case ruleEdit
    case globalSettingsEdit
    case ruleRemoval
}

public struct PauseActivationResolution<Payload> {
    public let payload: Payload
    public let performMaintenance: Bool

    public init(payload: Payload, performMaintenance: Bool) {
        self.payload = payload
        self.performMaintenance = performMaintenance
    }
}

public enum PauseActivationOutcome<Payload> {
    case unchanged
    case configuration
    case repair
    case resolved(Payload)
}

extension PauseActivationOutcome: Equatable where Payload: Equatable {}
extension PauseActivationOutcome: Sendable where Payload: Sendable {}

public struct PauseActivationCoordinator: Sendable {
    public private(set) var configurationState: ConfigurationLoadState
    public private(set) var foregroundState: ForegroundPauseState = .configuration
    private var hasHandledCurrentActivation = false
    private var hasProtectedState: Bool

    public init(
        configurationState: ConfigurationLoadState,
        hasProtectedState: Bool = false
    ) {
        self.configurationState = configurationState
        self.hasProtectedState = hasProtectedState
    }

    public mutating func configurationBecameKnownGood() {
        configurationState = .knownGood
        hasProtectedState = false
    }

    public mutating func configurationWasMissing(hasProtectedState: Bool = false) {
        configurationState = .missing
        self.hasProtectedState = hasProtectedState
    }

    public mutating func configurationLoadFailed() {
        configurationState = .failed
    }

    public mutating func configurationSaveCompleted(successfully: Bool) {
        guard successfully else { return }
        guard allowsConfigurationMutation(.pickerSelection) else { return }
        configurationBecameKnownGood()
    }

    public mutating func authorizationDidChange() {
        hasHandledCurrentActivation = false
    }

    public var requiresConfigurationRepair: Bool {
        switch configurationState {
        case .failed:
            true
        case .missing:
            hasProtectedState
        case .knownGood:
            false
        }
    }

    public var canDismissConfigurationRepair: Bool {
        !requiresConfigurationRepair
    }

    public func allowsConfigurationMutation(_ mutation: ConfigurationMutation) -> Bool {
        switch (configurationState, mutation) {
        case (.knownGood, _):
            true
        case (.missing, .pickerSelection):
            !hasProtectedState
        case (.missing, .ruleEdit),
             (.missing, .globalSettingsEdit),
             (.missing, .ruleRemoval),
             (.failed, _):
            false
        }
    }

    public mutating func countdownDidStart() {
        foregroundState = .countingDown
    }

    public mutating func grantDidStart() {
        foregroundState = .grantStarted
    }

    public mutating func returnedToConfiguration() {
        foregroundState = .configuration
    }

    public mutating func sceneDidBecomeInactive() {
        hasHandledCurrentActivation = false
        foregroundState = foregroundState.transitioned(for: .sceneBecameInactive)
    }

    public mutating func activate<Intent, Payload>(
        isAuthorized: Bool,
        consumeIntent: () throws -> Intent?,
        resolveIntent: (Intent) throws -> PauseActivationResolution<Payload>,
        cleanup: () -> Void,
        reconcile: () -> Void
    ) -> PauseActivationOutcome<Payload> {
        guard !hasHandledCurrentActivation else { return .unchanged }
        hasHandledCurrentActivation = true

        guard foregroundState != .grantStarted else { return .unchanged }

        if requiresConfigurationRepair {
            _ = try? consumeIntent()
            return .repair
        }
        guard isAuthorized else { return .configuration }

        switch configurationState {
        case .missing:
            do {
                return try consumeIntent() == nil ? .configuration : .repair
            } catch {
                return .repair
            }
        case .failed:
            return .repair
        case .knownGood:
            break
        }

        cleanup()
        reconcile()

        let intent: Intent
        do {
            guard let consumedIntent = try consumeIntent() else {
                return .configuration
            }
            intent = consumedIntent
        } catch {
            return .repair
        }

        let resolution: PauseActivationResolution<Payload>
        do {
            resolution = try resolveIntent(intent)
        } catch {
            return .repair
        }

        return .resolved(resolution.payload)
    }
}
