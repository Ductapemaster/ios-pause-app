import ManagedSettings
import PauseCore
import SwiftUI

/// One thing a scheduled change does. A change is one document replacing
/// another, so it can carry several of these at once.
enum ScheduledChange: Equatable {
    case removal(ApplicationToken)
    case addition(ApplicationToken)
    case allowance(
        ApplicationToken,
        sessionsPerDay: Int?,
        sessionLengthMinutes: Int?
    )
    case pauseDuration(seconds: Int)
}

/// A sentence the notice draws.
///
/// An app has no name Pause can read: `Label(token)` is the only thing that
/// renders one, and it renders a view rather than a string. So a sentence about
/// an app is carried as the token plus the words that follow it, and the view
/// puts the label where the subject goes.
enum ScheduledChangeSentence: Equatable {
    case aboutApp(ApplicationToken, predicate: String)
    case plain(String)
}

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

    /// What one document does to another, ordered as the notice reads them: a
    /// removal first, because it is the change a later save can replace and the
    /// one worth seeing go.
    static func changes(
        from inForce: ConfigurationDocument,
        to scheduled: ConfigurationDocument
    ) -> [ScheduledChange] {
        let scheduledRules = Dictionary(uniqueKeysWithValues: scheduled.rules.map { ($0.id, $0) })
        let scheduledTargets = Dictionary(
            uniqueKeysWithValues: scheduled.targets.map { ($0.ruleID, $0) }
        )
        let inForceRules = Dictionary(uniqueKeysWithValues: inForce.rules.map { ($0.id, $0) })

        var removals: [ScheduledChange] = []
        var additions: [ScheduledChange] = []
        var allowances: [ScheduledChange] = []

        for target in inForce.targets {
            guard let scheduledTarget = scheduledTargets[target.ruleID] else {
                removals.append(.removal(target.applicationToken))
                continue
            }
            // A target re-pointed at another application drops coverage of the
            // one it named and picks up another, which reads as both.
            guard scheduledTarget.applicationToken == target.applicationToken else {
                removals.append(.removal(target.applicationToken))
                additions.append(.addition(scheduledTarget.applicationToken))
                continue
            }
            guard let before = inForceRules[target.ruleID],
                  let after = scheduledRules[target.ruleID] else { continue }
            let sessionsPerDay = after.sessionsPerDay == before.sessionsPerDay
                ? nil
                : after.sessionsPerDay
            let sessionLengthMinutes = after.sessionLengthMinutes == before.sessionLengthMinutes
                ? nil
                : after.sessionLengthMinutes
            guard sessionsPerDay != nil || sessionLengthMinutes != nil else { continue }
            allowances.append(
                .allowance(
                    target.applicationToken,
                    sessionsPerDay: sessionsPerDay,
                    sessionLengthMinutes: sessionLengthMinutes
                )
            )
        }

        let inForceRuleIDs = Set(inForce.targets.map(\.ruleID))
        for target in scheduled.targets where !inForceRuleIDs.contains(target.ruleID) {
            additions.append(.addition(target.applicationToken))
        }

        var settings: [ScheduledChange] = []
        if scheduled.settings.pauseSeconds != inForce.settings.pauseSeconds {
            settings.append(.pauseDuration(seconds: scheduled.settings.pauseSeconds))
        }

        return removals + additions + allowances + settings
    }

    /// The notice's sentence. One change is named in full. Several are named by
    /// the first plus a count of the rest, which stays one line at three or four
    /// changes where naming each would not.
    static func sentence(
        for changes: [ScheduledChange],
        starting when: String
    ) -> ScheduledChangeSentence {
        guard let first = changes.first else {
            return .plain("A change to your rules starts \(when).")
        }
        let remainder = changes.count - 1
        let tail: String
        switch remainder {
        case 0: tail = " \(when)."
        case 1: tail = ", and 1 other change starts \(when)."
        default: tail = ", and \(remainder) other changes start \(when)."
        }

        switch first {
        case let .removal(token):
            return .aboutApp(token, predicate: "is being removed\(tail)")
        case let .addition(token):
            return .aboutApp(token, predicate: "is being added\(tail)")
        case let .allowance(token, sessionsPerDay, sessionLengthMinutes):
            return .aboutApp(
                token,
                predicate: "changes to \(allowance(sessionsPerDay, sessionLengthMinutes))\(tail)"
            )
        case let .pauseDuration(seconds):
            return .plain("The pause changes to \(count(seconds, "second"))\(tail)")
        }
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

/// The sentence shown wherever a scheduled change needs to be visible, with the
/// action that drops it.
struct ScheduledChangeNotice: View {
    @ObservedObject var model: AppModel
    let startDay: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sentence
            Button("Cancel change") {
                model.cancelScheduledChange()
            }
        }
    }

    /// Without a file there is no saved reset to name a day against, and no
    /// scheduled change either, so the generic phrase is the whole of that case.
    private var startPhrase: String {
        guard let file = model.configurationFile else { return "at the next reset" }
        return ScheduledChangeWording.phrase(for: startDay, in: file)
    }

    @ViewBuilder
    private var sentence: some View {
        switch ScheduledChangeWording.sentence(
            for: model.scheduledChanges,
            starting: startPhrase
        ) {
        case let .aboutApp(token, predicate):
            // The label holds the first line and the rest wraps beside it; the
            // app's name is the one part of the sentence Pause cannot measure or
            // shorten.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AppTokenLabel(applicationToken: token)
                Text(predicate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .plain(text):
            Text(text)
        }
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
