import Foundation
import PauseCore

/// A saved edit that has not reached its start day yet.
public struct PendingConfiguration: Codable, Equatable {
    public var document: ConfigurationDocument
    public var startDay: CalendarDay

    public init(document: ConfigurationDocument, startDay: CalendarDay) {
        self.document = document
        self.startDay = startDay
    }
}

/// What `configuration.json` holds: the rules in force now, and optionally a
/// scheduled replacement.
///
/// The pending document is selected at read time rather than promoted when its
/// start day arrives. Promotion would need a write, and the shield
/// configuration extension cannot write, so a shield rendering after the reset
/// would have no way to reach a configuration that had just taken effect.
public struct ConfigurationFile: Codable, Equatable {
    public var effective: ConfigurationDocument
    public var pending: PendingConfiguration?

    public init(effective: ConfigurationDocument, pending: PendingConfiguration? = nil) {
        self.effective = effective
        self.pending = pending
    }

    public func inForce(on logicalDay: CalendarDay) -> ConfigurationDocument {
        guard let pending, pending.startDay <= logicalDay else {
            return effective
        }
        return pending.document
    }

    /// The allowance day this instant falls in, resolved from the reset time in
    /// the effective document.
    ///
    /// The effective document is the right source and not merely a convenient
    /// one: a reset change applies immediately, so the effective document always
    /// carries the current reset; and in the one case where a reset change is
    /// deferred, the old reset is exactly what should still govern until the
    /// scheduled change lands.
    public func logicalDay(at instant: Date, calendar: Calendar = .current) -> CalendarDay {
        LogicalDay.containing(
            instant,
            resetMinuteOfDay: effective.settings.resetMinuteOfDay,
            calendar: calendar
        )
    }

    public func inForce(at instant: Date, calendar: Calendar = .current) -> ConfigurationDocument {
        inForce(on: logicalDay(at: instant, calendar: calendar))
    }
}
