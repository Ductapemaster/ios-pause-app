import Foundation
import ManagedSettings
import PauseCore

public enum RuleLookupError: LocalizedError, Equatable {
    case targetNotFound
    case duplicateTargets
    case ruleNotFound(UUID)
    case runtimeNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .targetNotFound:
            "Pause no longer has a rule for this app. Open Pause to repair it."
        case .duplicateTargets:
            "Pause has more than one rule for this app. Open Pause to repair it."
        case .ruleNotFound:
            "Pause cannot find this app's rule. Open Pause to repair it."
        case .runtimeNotFound:
            "Pause cannot find this app's session data. Open Pause to repair it."
        }
    }
}

public struct RuleEvaluation: Equatable {
    public let runtime: RuleRuntime
    public let decision: SessionDecision
}

public struct ResolvedRule {
    public let rule: AppRule
    public let target: RuleTarget
    public let evaluation: RuleEvaluation
}

public enum RuleLookup {
    public static func resolve(
        applicationToken: ApplicationToken,
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date,
        calendar: Calendar = .current
    ) throws -> ResolvedRule {
        let matchingTargets = configuration.targets.filter {
            $0.applicationToken == applicationToken
        }
        guard matchingTargets.count == 1, let target = matchingTargets.first else {
            if matchingTargets.isEmpty {
                throw RuleLookupError.targetNotFound
            }
            throw RuleLookupError.duplicateTargets
        }
        guard let rule = configuration.rules.first(where: { $0.id == target.ruleID }) else {
            throw RuleLookupError.ruleNotFound(target.ruleID)
        }
        guard let runtime = try runtimeRepository.load(ruleID: target.ruleID) else {
            throw RuleLookupError.runtimeNotFound(target.ruleID)
        }

        return ResolvedRule(
            rule: rule,
            target: target,
            evaluation: evaluate(rule: rule, runtime: runtime, now: now, calendar: calendar)
        )
    }

    public static func evaluate(
        rule: AppRule,
        runtime: RuleRuntime,
        now: Date,
        calendar: Calendar = .current
    ) -> RuleEvaluation {
        var currentRuntime = runtime
        currentRuntime.rollOver(to: CalendarDay(date: now, calendar: calendar))
        currentRuntime.clearExpiredSession(at: now)

        return RuleEvaluation(
            runtime: currentRuntime,
            decision: RulesEngine.decision(
                rule: rule,
                runtime: currentRuntime,
                today: currentRuntime.logicalDay,
                now: now
            )
        )
    }
}

public struct ShieldPresentation: Equatable, Sendable {
    public let subtitle: String
    public let primaryButtonTitle: String

    public init(rule: AppRule, decision: SessionDecision) {
        switch decision {
        case let .allowed(sessionNumber, _):
            // Counts this session and every one after it, so the number only
            // falls once a session is actually spent.
            let remaining = rule.sessionsPerDay - sessionNumber + 1
            subtitle = "\(remaining) session\(remaining == 1 ? "" : "s") left today"
            primaryButtonTitle = "Take a breath"
        case .refused(.dailyAllowanceExhausted):
            subtitle = "That's all for today."
            primaryButtonTitle = "Done for today"
        case .refused(.sessionAlreadyOpen):
            subtitle = "A session is already open"
            primaryButtonTitle = "Done for today"
        }
    }

    public static let repair = ShieldPresentation(
        subtitle: "Open Pause to repair this app",
        primaryButtonTitle: "Done for today"
    )

    private init(subtitle: String, primaryButtonTitle: String) {
        self.subtitle = subtitle
        self.primaryButtonTitle = primaryButtonTitle
    }
}
