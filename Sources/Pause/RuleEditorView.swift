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

            if let change = pendingChange, let file = model.configurationFile {
                Section {
                    Text(ScheduledChangeWording.description(of: change, in: file))
                    Button(change.kind.cancelTitle, role: change.kind.cancelRole) {
                        model.cancelScheduledChange(ruleID: ruleID)
                    }
                }
            }

            if pendingChange == nil {
                Section {
                    Button("Remove app", role: .destructive) {
                        removeRule()
                    }
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
                .disabled(pendingChange != nil)
            }
        }
        // The controls show the values in force, never a proposed value the
        // user cannot currently edit. Pending state changing — a deferred
        // save locking the controls around what was just typed, or a cancel
        // unlocking them again — is exactly when the in-force values and the
        // on-screen state can have drifted apart, in either direction, so
        // both transitions reseed from the same source.
        .onChange(of: pendingChange) { _, _ in
            reseedFromConfiguration()
        }
    }

    private let ruleID: UUID

    /// What is scheduled for this app, if anything. Everything the screen does
    /// differently under a pending change comes from this one lookup.
    private var pendingChange: PendingRuleChange? {
        model.pendingChange(forRuleID: ruleID)
    }

    /// Resets the on-screen controls to the values in force, discarding
    /// whatever the user had typed. Called whenever pending state changes,
    /// since that is exactly when a proposed value could otherwise be left
    /// showing: a deferred save just locked the controls around it, or a
    /// cancel just unlocked them without touching it. If the rule is no
    /// longer in `model.configuration` — removed out from under this screen
    /// — there is nothing to reseed to, so the on-screen values are left as
    /// they are; the row is gone from the list either way.
    private func reseedFromConfiguration() {
        guard let rule = model.configuration.rules.first(where: { $0.id == ruleID }) else {
            return
        }
        sessionsPerDay = rule.sessionsPerDay
        sessionLengthMinutes = rule.sessionLengthMinutes
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
