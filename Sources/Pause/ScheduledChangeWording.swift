import PauseCore
import SwiftUI

/// What a scheduled change is and when it starts, in the words the rules list
/// and the editor share.
enum ScheduledChangeWording {
    /// "tomorrow" for the ordinary case. Pause not being opened for a day leaves
    /// a start day that is neither tomorrow nor arrived, which reads as a date
    /// instead — formatted through `Date.formatted`, so the device locale
    /// decides the order of the fields.
    ///
    /// The file answers what tomorrow is, rather than a reset minute picked out
    /// here: the day being named was stamped by the file's own reset, so only
    /// that reset can say whether it is the next one.
    static func phrase(for day: CalendarDay, in file: ConfigurationFile, now: Date = Date()) -> String {
        if day == file.nextLogicalDay(after: now) {
            return "tomorrow"
        }
        guard let date = day.date(in: .current) else { return "at the next reset" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// One app's scheduled change, for the section under its controls. The
    /// screen already names the app, so the sentence has no subject.
    static func description(
        of change: PendingRuleChange,
        in file: ConfigurationFile,
        now: Date = Date()
    ) -> String {
        let when = phrase(for: change.startDay, in: file, now: now)
        switch change.kind {
        case .removal:
            return "Removal pending. Shielded as normal until it leaves Pause \(when)."
        case let .allowance(sessionsPerDay, sessionLengthMinutes):
            return "Changes to \(allowance(sessionsPerDay, sessionLengthMinutes)) \(when)."
        }
    }

    /// Names only the field that moved, so a setting that did not change is not
    /// read back as though it had.
    static func settingsDescription(
        of change: PendingSettingsChange,
        in file: ConfigurationFile,
        now: Date = Date()
    ) -> String {
        let when = phrase(for: change.startDay, in: file, now: now)
        switch (change.pauseSeconds, change.cooldownMinutes) {
        case let (seconds?, minutes?):
            return "The pause changes to \(count(seconds, "second")) and the "
                + "cooldown to \(cooldown(minutes)) \(when)."
        case let (seconds?, nil):
            return "The pause changes to \(count(seconds, "second")) \(when)."
        case let (nil, minutes?):
            return "The cooldown changes to \(cooldown(minutes)) \(when)."
        case (nil, nil):
            return "The settings change \(when)."
        }
    }

    /// Zero is the cooldown switched off, which "0 minutes" states less plainly.
    private static func cooldown(_ minutes: Int) -> String {
        minutes == 0 ? "off" : count(minutes, "minute")
    }

    /// The allowance names only the field that moved, so a session count that
    /// did not change is not read back as though it had.
    private static func allowance(_ sessionsPerDay: Int?, _ sessionLengthMinutes: Int?) -> String {
        switch (sessionsPerDay, sessionLengthMinutes) {
        case let (sessions?, minutes?):
            "\(count(sessions, "session")) of \(count(minutes, "minute"))"
        case let (sessions?, nil):
            count(sessions, "session")
        case let (nil, minutes?):
            "\(minutes)-minute sessions"
        case (nil, nil):
            "a new allowance"
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

extension CalendarDay {
    /// The day as a date, for formatting. A `CalendarDay` carries the fields a
    /// calendar needs to name the day and nothing else, so this can fail on a
    /// calendar that cannot form them.
    func date(in calendar: Calendar) -> Date? {
        calendar.date(
            from: DateComponents(era: era, year: year, month: month, day: day)
        )
    }
}
