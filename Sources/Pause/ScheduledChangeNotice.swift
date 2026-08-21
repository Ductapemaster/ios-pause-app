import PauseCore
import SwiftUI

/// When a scheduled change starts, in the words the rules list and the editor
/// share.
enum ScheduledChangeWording {
    /// "tomorrow" for the ordinary case. Pause not being opened for a day leaves
    /// a start day that is neither tomorrow nor arrived, which reads as a date
    /// instead — formatted through `Date.formatted`, so the device locale
    /// decides the order of the fields.
    static func phrase(for day: CalendarDay, now: Date = Date()) -> String {
        if day == LogicalDay.next(after: now) { return "tomorrow" }
        guard let date = day.date(in: .current) else { return "at the next reset" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// The sentence shown wherever a scheduled change needs to be visible, with the
/// action that drops it.
struct ScheduledChangeNotice: View {
    @ObservedObject var model: AppModel
    let startDay: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A change to your rules starts \(ScheduledChangeWording.phrase(for: startDay)).")
            Button("Cancel change") {
                model.cancelScheduledChange()
            }
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
