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
            Section {
                AppTokenLabel(applicationToken: applicationToken)
            }

            AllowanceSection(
                sessionsPerDay: $sessionsPerDay,
                sessionLengthMinutes: $sessionLengthMinutes,
                isEnabled: pendingChange == nil
            )

            if let change = pendingChange {
                Section {
                    if let file = model.configurationFile {
                        Text(ScheduledChangeWording.description(of: change, in: file))
                    }
                    Button(change.kind.cancelTitle) {
                        model.cancelScheduledChange(ruleID: ruleID)
                    }
                }
            }

            Section {
                Button("Remove app", role: .destructive) {
                    removeRule()
                }
                .disabled(pendingChange != nil)
            }
        }
        .navigationTitle("Allowance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(pendingChange != nil)
            }
        }
    }

    private let ruleID: UUID

    /// What is scheduled for this app, if anything. Everything the screen does
    /// differently under a pending change comes from this one lookup.
    private var pendingChange: PendingRuleChange? {
        model.pendingChange(forRuleID: ruleID)
    }

    private func save() {
        do {
            try model.updateRule(
                id: ruleID,
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            )
            // A save that waits stays on screen, so the wait is visible where it
            // was chosen, under the section that can cancel it. One that applied
            // at once is done.
            if pendingChange == nil {
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
