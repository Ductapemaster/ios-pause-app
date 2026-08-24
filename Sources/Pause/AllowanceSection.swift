import PauseCore
import SwiftUI

/// The two allowance controls — sessions per day and session length — as one
/// `Form` section, shared by every screen that lets the user choose them.
///
/// The footer is a parameter because the sentence depends on the screen: the
/// editor explains when the allowance renews, and a screen that is still adding
/// the app may say something else or nothing at all.
struct AllowanceSection: View {
    @Binding var sessionsPerDay: Int
    @Binding var sessionLengthMinutes: Int
    var footer: String? = "The daily allowance renews at the day reset."

    var body: some View {
        Section {
            Stepper(value: $sessionsPerDay, in: AppRuleLimits.sessionsPerDay) {
                LabeledContent("Sessions per day") {
                    Text("\(sessionsPerDay)")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
            }

            Stepper(value: $sessionLengthMinutes, in: AppRuleLimits.sessionLengthMinutes) {
                LabeledContent("Session length") {
                    Text("\(sessionLengthMinutes) min")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
            }
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }
}
