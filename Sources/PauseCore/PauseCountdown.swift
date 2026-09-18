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
    /// The scene left the foreground entirely. A transient loss of active
    /// status — a notification banner, a Control Center pull, the app switcher
    /// — is not this event: the user has not left, and a countdown they are
    /// still sitting in front of should survive it.
    case sceneLeftForeground
}

public enum ForegroundPauseState: Equatable, Sendable {
    case configuration
    case countingDown
    case grantStarted

    public func transitioned(for event: ForegroundPauseEvent) -> ForegroundPauseState {
        switch (self, event) {
        case (.countingDown, .sceneLeftForeground):
            .configuration
        case (.configuration, .sceneLeftForeground), (.grantStarted, .sceneLeftForeground):
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

/// Why `activate` returned the outcome it did. Instrumentation only — nothing
/// branches on this. A route name alone cannot separate a shield press that was
/// discarded from one that resolved to the same screen for a different reason,
/// which is what the log line has to answer.
public enum PauseActivationReason: String, Sendable {
    case activationAlreadyHandled
    case grantInProgress
    case configurationRepairRequired
    case notAuthorized
    case configurationMissingNoIntent
    case configurationMissingWithIntent
    case configurationMissingIntentUnreadable
    case configurationFailed
    case intentNil
    case intentUnreadable
    case intentUnresolvable
    case intentResolved
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

    public mutating func sceneDidLeaveForeground() {
        hasHandledCurrentActivation = false
        foregroundState = foregroundState.transitioned(for: .sceneLeftForeground)
    }

    /// `hasPendingIntent` reopens an activation already marked handled. Only
    /// `.background` clears the mark, and leaving by the app switcher never
    /// reaches it, so a shield press made from there would otherwise be
    /// discarded. A banner or a Control Center pull leaves no intent, so a
    /// countdown still survives those.
    public mutating func activate<Intent, Payload>(
        isAuthorized: Bool,
        hasPendingIntent: () -> Bool = { false },
        consumeIntent: () throws -> Intent?,
        resolveIntent: (Intent) throws -> PauseActivationResolution<Payload>,
        cleanup: () -> Void,
        reconcile: () -> Void,
        reasonSink: (PauseActivationReason) -> Void = { _ in }
    ) -> PauseActivationOutcome<Payload> {
        guard !hasHandledCurrentActivation || hasPendingIntent() else {
            reasonSink(.activationAlreadyHandled)
            return .unchanged
        }
        hasHandledCurrentActivation = true

        guard foregroundState != .grantStarted else {
            reasonSink(.grantInProgress)
            return .unchanged
        }

        if requiresConfigurationRepair {
            _ = try? consumeIntent()
            reasonSink(.configurationRepairRequired)
            return .repair
        }
        guard isAuthorized else {
            reasonSink(.notAuthorized)
            return .configuration
        }

        switch configurationState {
        case .missing:
            do {
                if try consumeIntent() == nil {
                    reasonSink(.configurationMissingNoIntent)
                    return .configuration
                }
                reasonSink(.configurationMissingWithIntent)
                return .repair
            } catch {
                reasonSink(.configurationMissingIntentUnreadable)
                return .repair
            }
        case .failed:
            reasonSink(.configurationFailed)
            return .repair
        case .knownGood:
            break
        }

        cleanup()
        reconcile()

        let intent: Intent
        do {
            guard let consumedIntent = try consumeIntent() else {
                reasonSink(.intentNil)
                return .configuration
            }
            intent = consumedIntent
        } catch {
            reasonSink(.intentUnreadable)
            return .repair
        }

        let resolution: PauseActivationResolution<Payload>
        do {
            resolution = try resolveIntent(intent)
        } catch {
            reasonSink(.intentUnresolvable)
            return .repair
        }

        reasonSink(.intentResolved)
        return .resolved(resolution.payload)
    }
}
