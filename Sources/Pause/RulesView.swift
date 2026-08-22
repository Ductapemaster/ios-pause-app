import FamilyControls
import PauseCore
import SwiftUI

struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var isPickerPresented = false

    var body: some View {
        Group {
            if model.configuration.rules.isEmpty {
                emptyView
            } else {
                configuredView
            }
        }
        .navigationTitle("Pause")
        .familyActivityPicker(
            title: "Choose apps",
            footerText: pickerExplanation,
            isPresented: $isPickerPresented,
            selection: $model.pickerSelection
        )
        .onChange(of: isPickerPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            applyPickerSelection()
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("No apps selected")
                .font(.title.bold())

            Text("Choose the apps where you want a short pause before each allowed session.")
                .foregroundStyle(.secondary)

            Button("Choose apps") {
                isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)

            Text(pickerExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var configuredView: some View {
        Form {
            if let startDay = model.pendingChangeStartDay {
                Section {
                    ScheduledChangeNotice(model: model, startDay: startDay)
                }
            }

            Section("Apps") {
                ForEach(model.configuration.rules) { rule in
                    if let target = model.configuration.targets.first(where: { $0.ruleID == rule.id }) {
                        if model.ruleIDsPendingRemoval.contains(rule.id) {
                            pendingRemovalRow(rule: rule, target: target)
                        } else {
                            NavigationLink {
                                RuleEditorView(
                                    model: model,
                                    rule: rule,
                                    applicationToken: target.applicationToken
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AppTokenLabel(applicationToken: target.applicationToken)
                                    Text("\(rule.sessionsPerDay) × \(rule.sessionLengthMinutes) min")
                                        .font(.system(.subheadline, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Stepper(value: pauseSeconds, in: 1...120) {
                    LabeledContent("Pause duration") {
                        Text("\(model.configuration.settings.pauseSeconds) sec")
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    }
                }
            } footer: {
                Text("The pause shown before every allowed session.")
            }

            Section {
                Button("Edit apps") {
                    isPickerPresented = true
                }
            } footer: {
                Text(pickerExplanation)
            }
        }
    }

    /// A rule on its way out: still in force, still shielding, so it keeps its
    /// row. It is drawn faded and marked with the day it goes, and it is not a
    /// link — the editor saves a document built from the rules in force, which
    /// would write over the scheduled removal and quietly cancel it.
    private func pendingRemovalRow(rule: AppRule, target: RuleTarget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppTokenLabel(applicationToken: target.applicationToken)
                .opacity(0.5)

            Text("\(rule.sessionsPerDay) × \(rule.sessionLengthMinutes) min")
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.tertiary)

            Text("Removing \(removalPhrase)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Cancel removal") {
                model.cancelScheduledChange()
            }
            .buttonStyle(.borderless)
            .font(.footnote)
        }
    }

    private var removalPhrase: String {
        guard let startDay = model.pendingChangeStartDay else { return "at the next reset" }
        return ScheduledChangeWording.phrase(
            for: startDay,
            resetMinuteOfDay: model.configuration.settings.resetMinuteOfDay
        )
    }

    private var pauseSeconds: Binding<Int> {
        Binding(
            get: { model.configuration.settings.pauseSeconds },
            set: { seconds in
                do {
                    try model.updatePauseSeconds(seconds)
                } catch {
                    model.present(error)
                }
            }
        )
    }

    private var pickerExplanation: String {
        "Pause saves only individual apps. Category and website selections are not saved."
    }

    private func applyPickerSelection() {
        do {
            try model.applyPickerSelection()
        } catch {
            model.present(error, title: "Couldn't update apps")
        }
    }
}
