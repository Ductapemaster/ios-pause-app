import Foundation
import ManagedSettings
import PauseCore

public enum ShieldPrimaryActionError: LocalizedError, Equatable {
    case configurationMissing

    public var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "Pause has no configuration to resolve this app against."
        }
    }
}

/// Decides what the shield's primary button does when it is pressed.
public struct ShieldPrimaryAction {
    /// A refusal is a decision about sessions; a failure means the decision
    /// could not be made. They must not share an answer, so there are three.
    /// Every refusal — the allowance spent, a session already open, an app the
    /// configuration cannot resolve — shows a button reading "Done for today",
    /// which is a promise to dismiss.
    public enum Outcome: Equatable {
        /// A session is available and has been recorded as intended.
        case openPause
        /// Nothing to start, so close the shielded app.
        case dismiss
        /// The decision could not be reached. Leave the shield standing: the
        /// user may well have a session available, and closing their app on a
        /// transient failure spends nothing but tells them the day is over.
        case keepShield
    }

    private let directoryURL: URL
    private let intentStore: ShieldIntentStore
    private let stateLock: AppGroupFileLock

    public init(
        directoryURL: URL,
        intentStore: ShieldIntentStore = ShieldIntentStore(),
        stateLock: AppGroupFileLock? = nil
    ) {
        self.directoryURL = directoryURL
        self.intentStore = intentStore
        self.stateLock = stateLock ?? AppGroupFileLock(directoryURL: directoryURL)
    }

    public init(
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        intentStore: ShieldIntentStore = ShieldIntentStore()
    ) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL(), intentStore: intentStore)
    }

    public func resolve(
        applicationToken: ApplicationToken,
        now: Date,
        calendar: Calendar = .current,
        errorSink: (String) -> Void = { _ in }
    ) -> Outcome {
        // Only the acquisition can escape the `Result`, so a failure to take the
        // lock is told apart from anything the decision itself throws.
        let decision: Result<Outcome, Error>
        do {
            decision = try stateLock.withLock {
                Result { try decide(applicationToken: applicationToken, now: now, calendar: calendar) }
            }
        } catch {
            errorSink("Shield action could not lock shared state: \(String(describing: error))")
            return .keepShield
        }

        do {
            return try decision.get()
        } catch {
            errorSink("Shield action failed: \(String(describing: error))")
            return .dismiss
        }
    }

    private func decide(
        applicationToken: ApplicationToken,
        now: Date,
        calendar: Calendar
    ) throws -> Outcome {
        guard let file = try ConfigurationStore(directoryURL: directoryURL).loadFile() else {
            throw ShieldPrimaryActionError.configurationMissing
        }
        let resolved = try RuleLookup.resolve(
            applicationToken: applicationToken,
            configurationFile: file,
            runtimeRepository: RuntimeRepository(directoryURL: directoryURL),
            now: now,
            calendar: calendar
        )
        guard case .allowed = resolved.evaluation.decision else {
            return .dismiss
        }
        try intentStore.write(ShieldIntent(applicationToken: applicationToken, createdAt: now))
        return .openPause
    }
}
