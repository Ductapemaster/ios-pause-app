import Foundation
import PauseCore

/// Judges whether one configuration permits more app use than another.
///
/// The judgment is per unit: one rule together with the target naming its app,
/// plus global settings as a unit of their own. A document is a loosening when
/// any of its units is, which is the question a reader of the whole document
/// asks; a save asks it one unit at a time instead, so that a decision about one
/// app does not hold up a decision about another.
public enum ConfigurationComparison {
    /// One rule and the target naming its app. Absent means the app is not
    /// covered: absent before is an app being added, absent after is one whose
    /// coverage is being dropped.
    public struct RuleUnit: Equatable {
        public var rule: AppRule
        public var target: RuleTarget

        public init(rule: AppRule, target: RuleTarget) {
            self.rule = rule
            self.target = target
        }
    }

    public static func units(of document: ConfigurationDocument) -> [UUID: RuleUnit] {
        let rulesByID = Dictionary(uniqueKeysWithValues: document.rules.map { ($0.id, $0) })
        return document.targets.reduce(into: [:]) { units, target in
            guard let rule = rulesByID[target.ruleID] else { return }
            units[target.ruleID] = RuleUnit(rule: rule, target: target)
        }
    }

    public static func isLoosening(from before: RuleUnit?, to after: RuleUnit?) -> Bool {
        guard let before else {
            // Nothing covered this app before, so nothing it does now permits
            // more than it did. Covering it is a tightening.
            return false
        }
        guard let after else {
            // Coverage dropped, which is how an app leaves Pause.
            return true
        }
        if after.rule.sessionsPerDay > before.rule.sessionsPerDay { return true }
        if after.rule.sessionLengthMinutes > before.rule.sessionLengthMinutes { return true }
        // A target re-pointed at another application drops coverage of the app
        // it named before.
        return after.target.applicationToken != before.target.applicationToken
    }

    public static func isLoosening(from before: GlobalSettings, to after: GlobalSettings) -> Bool {
        after.pauseSeconds < before.pauseSeconds
    }

    public static func isLoosening(
        from before: ConfigurationDocument,
        to after: ConfigurationDocument
    ) -> Bool {
        if isLoosening(from: before.settings, to: after.settings) { return true }
        let afterUnits = units(of: after)
        for (ruleID, beforeUnit) in units(of: before) {
            if isLoosening(from: beforeUnit, to: afterUnits[ruleID]) { return true }
        }
        return false
    }
}
