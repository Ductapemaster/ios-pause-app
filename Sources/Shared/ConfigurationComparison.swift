import Foundation
import PauseCore

/// Judges whether one configuration permits more app use than another.
///
/// The edit is judged whole: any loosening anywhere defers the entire edit.
/// Applying part of an edit now and part tomorrow would mean storing a
/// difference rather than a document, which is not worth the precision.
public enum ConfigurationComparison {
    public static func isLoosening(
        from before: ConfigurationDocument,
        to after: ConfigurationDocument
    ) -> Bool {
        if after.settings.pauseSeconds < before.settings.pauseSeconds {
            return true
        }

        let afterRules = Dictionary(uniqueKeysWithValues: after.rules.map { ($0.id, $0) })
        for rule in before.rules {
            guard let updated = afterRules[rule.id] else { continue }
            if updated.sessionsPerDay > rule.sessionsPerDay { return true }
            if updated.sessionLengthMinutes > rule.sessionLengthMinutes { return true }
        }

        let afterTargets = Dictionary(uniqueKeysWithValues: after.targets.map { ($0.ruleID, $0) })
        for target in before.targets {
            // A target that disappears, and one re-pointed at another
            // application, both drop coverage of the app it named.
            guard let updated = afterTargets[target.ruleID] else { return true }
            if updated.applicationToken != target.applicationToken { return true }
        }

        return false
    }
}
