import Foundation
import PauseCore

/// Decides what a saved edit changes now and what waits for the next reset,
/// one unit at a time.
///
/// A save rebuilds the whole document, so what it left as the rules in force is
/// what it had no opinion about. Those units keep whatever was already
/// scheduled for them; the units it did state differently take what it says.
/// Each resulting unit then applies at once unless it loosens, in which case
/// only the scheduled document carries it.
public enum ConfigurationSaveRouter {
    public static func route(
        candidate: ConfigurationDocument,
        into existing: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) throws -> ConfigurationFile {
        let inForce = existing.inForce(at: now, calendar: calendar)
        let scheduled = existing.pending?.document

        let inForceUnits = ConfigurationComparison.units(of: inForce)
        let candidateUnits = ConfigurationComparison.units(of: candidate)
        let scheduledUnits = scheduled.map(ConfigurationComparison.units(of:))

        var immediateUnits: [ConfigurationComparison.RuleUnit] = []
        var scheduledResultUnits: [ConfigurationComparison.RuleUnit] = []

        for ruleID in orderedRuleIDs(inForce: inForce, candidate: candidate, scheduled: scheduled) {
            let inForceUnit = inForceUnits[ruleID]
            let candidateUnit = candidateUnits[ruleID]
            let target: ConfigurationComparison.RuleUnit?
            if candidateUnit != inForceUnit {
                target = candidateUnit
            } else if let scheduledUnits {
                target = scheduledUnits[ruleID]
            } else {
                target = inForceUnit
            }

            if let target { scheduledResultUnits.append(target) }
            let immediate = ConfigurationComparison.isLoosening(from: inForceUnit, to: target)
                ? inForceUnit
                : target
            if let immediate { immediateUnits.append(immediate) }
        }

        let targetSettings: GlobalSettings
        if candidate.settings != inForce.settings {
            targetSettings = candidate.settings
        } else {
            targetSettings = scheduled?.settings ?? inForce.settings
        }
        let immediateSettings = ConfigurationComparison.isLoosening(
            from: inForce.settings,
            to: targetSettings
        ) ? inForce.settings : targetSettings

        let immediate = try document(settings: immediateSettings, units: immediateUnits)
        let scheduledResult = try document(settings: targetSettings, units: scheduledResultUnits)

        var routed = ConfigurationFile(effective: immediate, pending: nil)
        guard scheduledResult != immediate else { return routed }
        // The start day is read out of the file being returned, not the one
        // being replaced: a save that moves the reset changes the boundary the
        // label will be compared against, and the two have to be the same one.
        routed.pending = PendingConfiguration(
            document: scheduledResult,
            startDay: routed.nextLogicalDay(after: now, calendar: calendar)
        )
        return routed
    }

    /// Rule order is user-visible in the rules list, so the documents this
    /// builds keep the in-force order and append what the candidate adds, then
    /// anything only the scheduled document still names.
    private static func orderedRuleIDs(
        inForce: ConfigurationDocument,
        candidate: ConfigurationDocument,
        scheduled: ConfigurationDocument?
    ) -> [UUID] {
        var ordered = inForce.targets.map(\.ruleID)
        var known = Set(ordered)
        for ruleID in candidate.targets.map(\.ruleID) where !known.contains(ruleID) {
            ordered.append(ruleID)
            known.insert(ruleID)
        }
        // A unit only the scheduled document names is an app added by a save
        // this router made before it judged per app, which deferred the whole
        // edit and so left the addition waiting. Walking it here is what covers
        // that app rather than dropping it: an addition does not loosen, so the
        // per-unit judgment lands it in both documents and the wait ends.
        for ruleID in scheduled?.targets.map(\.ruleID) ?? [] where !known.contains(ruleID) {
            ordered.append(ruleID)
            known.insert(ruleID)
        }
        return ordered
    }

    private static func document(
        settings: GlobalSettings,
        units: [ConfigurationComparison.RuleUnit]
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: settings,
            rules: units.map(\.rule),
            targets: units.map(\.target)
        )
    }
}
