import ManagedSettings
import PauseCore
import SwiftUI

struct RuleEditorView: View {
    @ObservedObject var model: AppModel
    let applicationToken: ApplicationToken

    @Environment(\.dismiss) private var dismiss
    @State private var sessionsPerDay: Int
    @State private var sessionLengthMinutes: Int

    init(model: AppModel, rule: AppRule, applicationToken: ApplicationToken) {
        self.model = model
        self.applicationToken = applicationToken
        _sessionsPerDay = State(initialValue: rule.sessionsPerDay)
        _sessionLengthMinutes = State(initialValue: rule.sessionLengthMinutes)
        ruleID = rule.id
    }

    var body: some View {
        Form {
            if let startDay = model.pendingChangeStartDay {
                Section {
                    ScheduledChangeNotice(model: model, startDay: startDay)
                }
            }

            Section {
                AppTokenLabel(applicationToken: applicationToken)
            }

            Section {
                Stepper(value: $sessionsPerDay, in: 1...20) {
                    LabeledContent("Sessions per day") {
                        Text("\(sessionsPerDay)")
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    }
                }

                Stepper(value: $sessionLengthMinutes, in: 1...120) {
                    LabeledContent("Session length") {
                        Text("\(sessionLengthMinutes) min")
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    }
                }
            } footer: {
                Text("The daily allowance renews at the day reset.")
            }

            Section {
                Button("Remove app", role: .destructive) {
                    removeRule()
                }
            }
        }
        .navigationTitle("Allowance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
    }

    private let ruleID: UUID

    private func save() {
        do {
            try model.updateRule(
                id: ruleID,
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            )
            // A save that waits stays on screen under its notice, so the wait is
            // visible where it was chosen. One that applied at once is done.
            if !model.lastSaveDeferredPart {
                dismiss()
            }
        } catch {
            model.present(error)
        }
    }

    private func removeRule() {
        do {
            try model.removeRule(id: ruleID)
            dismiss()
        } catch {
            model.present(error, title: "Couldn't remove app")
        }
    }
}
