import FamilyControls
import Foundation
import ManagedSettings
import PauseCore

public enum ConfigurationError: Error, Equatable {
    case duplicateRule(UUID)
    case duplicateTarget(UUID)
    case missingTarget(UUID)
    case missingRule(UUID)
}

public struct RuleTarget: Codable, Equatable, Identifiable {
    public var id: UUID { ruleID }
    public var ruleID: UUID
    public var applicationToken: ApplicationToken
    public var launchRoute: LaunchRoute?

    public init(ruleID: UUID, applicationToken: ApplicationToken, launchRoute: LaunchRoute?) {
        self.ruleID = ruleID
        self.applicationToken = applicationToken
        self.launchRoute = launchRoute
    }
}

public struct ConfigurationDocument: Codable, Equatable {
    public var settings: GlobalSettings
    public var rules: [AppRule]
    public var targets: [RuleTarget]

    public init(settings: GlobalSettings, rules: [AppRule], targets: [RuleTarget]) throws {
        self.settings = settings
        self.rules = rules
        self.targets = targets
    }

    public func validate() throws {
        var ruleIDs = Set<UUID>()
        for rule in rules {
            guard ruleIDs.insert(rule.id).inserted else {
                throw ConfigurationError.duplicateRule(rule.id)
            }
        }

        var targetRuleIDs = Set<UUID>()
        for target in targets {
            guard targetRuleIDs.insert(target.ruleID).inserted else {
                throw ConfigurationError.duplicateTarget(target.ruleID)
            }
        }

        for ruleID in ruleIDs where !targetRuleIDs.contains(ruleID) {
            throw ConfigurationError.missingTarget(ruleID)
        }
        for ruleID in targetRuleIDs where !ruleIDs.contains(ruleID) {
            throw ConfigurationError.missingRule(ruleID)
        }
    }
}
