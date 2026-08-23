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
    /// The button has exactly two answers, and no third that leaves it dead:
    /// it either starts a session or dismisses. Every refusal — the allowance
    /// spent, a session already open, an app the configuration cannot resolve —
    /// shows a button reading "Done for today", which is a promise to dismiss.
    public enum Outcome: Equatable {
        /// A session is available and has been recorded as intended.
        case openPause
        /// Nothing to start, so close the shielded app.
        case dismiss
    }

    private let directoryURL: URL
    private let intentStore: ShieldIntentStore

    public init(directoryURL: URL, intentStore: ShieldIntentStore = ShieldIntentStore()) {
        self.directoryURL = directoryURL
        self.intentStore = intentStore
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
        do {
            let stateLock = AppGroupFileLock(directoryURL: directoryURL)
            return try stateLock.withLock { () -> Outcome in
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
                try intentStore.write(
                    ShieldIntent(applicationToken: applicationToken, createdAt: now)
                )
                return .openPause
            }
        } catch {
            errorSink("Shield action failed: \(String(describing: error))")
            return .dismiss
        }
    }
}
