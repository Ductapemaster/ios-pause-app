import Foundation
import PauseCore

/// Decides whether a saved edit takes effect now or at the next reset.
public enum ConfigurationSaveRouter {
    public static func route(
        candidate: ConfigurationDocument,
        into existing: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) -> ConfigurationFile {
        let inForce = existing.inForce(on: LogicalDay.containing(now, calendar: calendar))
        guard ConfigurationComparison.isLoosening(from: inForce, to: candidate) else {
            // Tightening always wins, so a scheduled loosening cannot survive a
            // later decision to be stricter.
            return ConfigurationFile(effective: candidate, pending: nil)
        }
        return ConfigurationFile(
            effective: inForce,
            pending: PendingConfiguration(
                document: candidate,
                startDay: LogicalDay.next(after: now, calendar: calendar)
            )
        )
    }
}
