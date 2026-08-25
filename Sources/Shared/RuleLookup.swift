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
    /// Resolves against the whole file rather than a document, because the
    /// answer needs two things the file alone can pair: which document is in
    /// force, and which allowance day the session count is charged to. Both come
    /// from the effective document's reset, so taking the file is what stops a
    /// caller resolving one against the other's frame.
    public static func resolve(
        applicationToken: ApplicationToken,
        configurationFile: ConfigurationFile,
        runtimeRepository: any RuntimeReading,
        now: Date,
        calendar: Calendar = .current
    ) throws -> ResolvedRule {
        let configuration = configurationFile.inForce(at: now, calendar: calendar)
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
            evaluation: evaluate(
                rule: rule,
                runtime: runtime,
                settings: configuration.settings,
                logicalDay: configurationFile.logicalDay(at: now, calendar: calendar),
                now: now
            )
        )
    }

    /// The day is passed in rather than derived here. Deriving it would need a
    /// reset minute, and the only reset that may decide an allowance day is the
    /// effective document's — which this function, holding one rule and one
    /// runtime, is not placed to read. It takes no calendar for the same reason:
    /// nothing here has an instant to turn into a day.
    public static func evaluate(
        rule: AppRule,
        runtime: RuleRuntime,
        settings: GlobalSettings,
        logicalDay: CalendarDay,
        now: Date
    ) -> RuleEvaluation {
        var currentRuntime = runtime
        currentRuntime.rollOver(to: logicalDay)
        currentRuntime.clearExpiredSession(at: now)

        return RuleEvaluation(
            runtime: currentRuntime,
            decision: RulesEngine.decision(
                rule: rule,
                runtime: currentRuntime,
                settings: settings,
                today: currentRuntime.logicalDay,
                now: now
            )
        )
    }
}

public struct ShieldPresentation: Equatable, Sendable {
    public let subtitle: String
    public let primaryButtonTitle: String
    /// Nil on a refusal, where the shield shows one button. A second button is
    /// there to offer a way out beside the pause; where nothing can be started
    /// the primary button already is that way out, so a second one would only
    /// restate it.
    public let secondaryButtonTitle: String?

    public init(rule: AppRule, decision: SessionDecision) {
        switch decision {
        case let .allowed(sessionNumber, _):
            // Counts this session and every one after it, so the number only
            // falls once a session is actually spent.
            let remaining = rule.sessionsPerDay - sessionNumber + 1
            subtitle = "\(remaining) session\(remaining == 1 ? "" : "s") left today"
            primaryButtonTitle = "Take a breath"
            secondaryButtonTitle = "Not now"
        case .refused(.dailyAllowanceExhausted):
            subtitle = "That's all for today."
            primaryButtonTitle = Self.refusalButtonTitle
            secondaryButtonTitle = nil
        case .refused(.sessionAlreadyOpen):
            subtitle = "A session is already open"
            primaryButtonTitle = Self.refusalButtonTitle
            secondaryButtonTitle = nil
        case let .refused(.coolingDown(until)):
            // An end time rather than a countdown: `ShieldConfiguration` is
            // returned once per render and no API updates a shield already
            // standing, so a countdown would hold the second it was built with.
            subtitle = "Cooling down until \(Self.timeFormatter.string(from: until))."
            primaryButtonTitle = Self.refusalButtonTitle
            secondaryButtonTitle = nil
        }
    }

    /// Says only what the press does. The refusal itself is the subtitle's job,
    /// which is what keeps one label honest across all three refusals — an
    /// allowance that is spent, a session already running, and an app the
    /// configuration cannot resolve are three different reasons for the same
    /// single way out.
    static let refusalButtonTitle = "Close"

    /// The device locale decides how the time reads.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// The subtitle names opening Pause as something for the user to do, not as
    /// something the button does: the configuration extension cannot launch the
    /// app, so a button promising it could not keep the promise.
    public static let repair = ShieldPresentation(
        subtitle: "Pause can't check this app. Open Pause to fix it.",
        primaryButtonTitle: refusalButtonTitle
    )

    private init(subtitle: String, primaryButtonTitle: String) {
        self.subtitle = subtitle
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = nil
    }
}
