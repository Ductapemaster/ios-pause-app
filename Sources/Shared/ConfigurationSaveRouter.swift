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
        let inForce = existing.inForce(on: LogicalDay.containing(now, calendar: calendar))
        let scheduled = existing.pending?.document

        let inForceUnits = ConfigurationComparison.units(of: inForce)
        let candidateUnits = ConfigurationComparison.units(of: candidate)
        let scheduledUnits = scheduled.map(ConfigurationComparison.units(of:))

        var immediateUnits: [ConfigurationComparison.RuleUnit] = []
        var scheduledResultUnits: [ConfigurationComparison.RuleUnit] = []

        for ruleID in orderedRuleIDs(inForce: inForce, candidate: candidate) {
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

        guard scheduledResult != immediate else {
            return ConfigurationFile(effective: immediate, pending: nil)
        }
        return ConfigurationFile(
            effective: immediate,
            pending: PendingConfiguration(
                document: scheduledResult,
                startDay: LogicalDay.next(after: now, calendar: calendar)
            )
        )
    }

    /// Rule order is user-visible in the rules list, so the documents this
    /// builds keep the in-force order and append only what the candidate adds.
    /// A unit named by the scheduled document alone is ignored: a scheduled
    /// document can only hold units the effective one holds, since an addition
    /// is a tightening and never waits.
    private static func orderedRuleIDs(
        inForce: ConfigurationDocument,
        candidate: ConfigurationDocument
    ) -> [UUID] {
        var ordered = inForce.targets.map(\.ruleID)
        let known = Set(ordered)
        ordered.append(contentsOf: candidate.targets.map(\.ruleID).filter { !known.contains($0) })
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
