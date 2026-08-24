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
        Text("A change to your rules starts \(startPhrase).")
    }
}
