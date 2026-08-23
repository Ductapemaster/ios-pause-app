import Foundation
import PauseCore

/// How many sessions each rule has charged against the current allowance day.
///
/// The sibling of `ShieldStateReader`: that one answers what the shield should
/// say about a single app, this one answers what the list should show for every
/// app. Both take the configuration file rather than a document, because the
/// allowance day comes from the effective document's reset and only the file can
/// pair the two.
public struct RuleUsageReader {
    private let runtimeReader: any RuntimeReading

    public init(runtimeReader: any RuntimeReading) {
        self.runtimeReader = runtimeReader
    }

    /// Sessions charged per rule, keyed by rule ID.
    ///
    /// The stored count rolls over lazily, so a record keeps an earlier day's
    /// number until something touches it. `RuleLookup.evaluate` is what resolves
    /// that — it rolls the runtime to the day and writes nothing, so asking it
    /// for a display is free of side effects. Counting here instead would be a
    /// second implementation of which day a session is charged to, and the two
    /// would agree only until one was edited.
    ///
    /// A rule whose runtime is missing or unreadable is absent from the result
    /// rather than present with a wrong count: the list shows no number instead
    /// of a false one.
    public func sessionsUsed(
        in configurationFile: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) -> [UUID: Int] {
        let configuration = configurationFile.inForce(at: now, calendar: calendar)
        let logicalDay = configurationFile.logicalDay(at: now, calendar: calendar)

        return configuration.rules.reduce(into: [:]) { used, rule in
            guard let runtime = try? runtimeReader.load(ruleID: rule.id) else { return }
            used[rule.id] = RuleLookup.evaluate(
                rule: rule,
                runtime: runtime,
                logicalDay: logicalDay,
                now: now
            ).runtime.sessionsStarted
        }
    }
}
