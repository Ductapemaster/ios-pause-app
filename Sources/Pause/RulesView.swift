import FamilyControls
import ManagedSettings
import PauseCore
import SwiftUI

struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var isPickerPresented = false
    @State private var pendingAddition: PendingAddition?

    var body: some View {
        Group {
            if model.configuration.rules.isEmpty {
                emptyView
            } else {
                configuredView
            }
        }
        .navigationTitle("Pause")
        .sheet(isPresented: $isPickerPresented) {
            AppPickerSheet(
                initialSelection: model.pickerSelection,
                explanation: pickerExplanation,
                onSave: savePickerSelection
            )
        }
        .sheet(item: $pendingAddition) { addition in
            NewAppSetupSheet(applicationTokens: addition.applicationTokens) { allowances in
                commit(addition.selection, newAppAllowances: allowances)
            }
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
                                HStack {
                                    AppTokenLabel(applicationToken: target.applicationToken)
                                    Spacer()
                                    Text(usageText(for: rule))
                                        .font(.system(.body, design: .rounded).monospacedDigit())
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

                Picker(selection: resetMinuteOfDay) {
                    ForEach(Array(stride(from: 0, through: 1425, by: 15)), id: \.self) { minute in
                        Text(Self.resetLabel(for: minute)).tag(minute)
                    }
                } label: {
                    Text("Day reset")
                }
            } footer: {
                Text("The pause shown before every allowed session, and the time each day's sessions renew.")
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

            Text(usageText(for: rule))
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
        guard let startDay = model.pendingChangeStartDay,
              let file = model.configurationFile else { return "at the next reset" }
        return ScheduledChangeWording.phrase(for: startDay, in: file)
    }

    /// Empty when the rule has no count — a runtime that is missing or
    /// unreadable shows nothing rather than a number that would be wrong.
    private func usageText(for rule: AppRule) -> String {
        guard let used = model.sessionsUsedByRule[rule.id] else { return "" }
        return "\(used)/\(rule.sessionsPerDay)"
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

    private var resetMinuteOfDay: Binding<Int> {
        Binding(
            get: { model.configuration.settings.resetMinuteOfDay },
            set: { minute in
                do {
                    try model.setResetMinuteOfDay(minute)
                } catch {
                    model.present(error)
                }
            }
        )
    }

    private static func resetLabel(for minute: Int) -> String {
        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var pickerExplanation: String {
        "Pause saves only individual apps. Category and website selections are not saved."
    }

    /// A picker save that adds apps, held while the user gives each of them an
    /// allowance. The whole selection is carried along so the save that finally
    /// runs is the one the user pressed Save on.
    private struct PendingAddition: Identifiable {
        let id = UUID()
        let selection: FamilyActivitySelection
        let applicationTokens: [ApplicationToken]
    }

    /// Routes a saved picker selection: apps being added need an allowance
    /// before anything is written, so the save waits for the setup sheet.
    /// A selection that only drops apps has nothing to choose and goes straight
    /// through.
    private func savePickerSelection(_ selection: FamilyActivitySelection) {
        let existingTokens = Set(model.configuration.targets.map(\.applicationToken))
        let addedTokens = selection.applicationTokens.subtracting(existingTokens)

        guard !addedTokens.isEmpty else {
            commit(selection, newAppAllowances: [:])
            return
        }
        pendingAddition = PendingAddition(
            selection: selection,
            applicationTokens: Array(addedTokens)
        )
    }

    private func commit(
        _ selection: FamilyActivitySelection,
        newAppAllowances: [ApplicationToken: AppRule.Allowance]
    ) {
        let restoreSelection = model.pickerSelection
        model.pickerSelection = selection
        do {
            try model.applyPickerSelection(newAppAllowances: newAppAllowances)
        } catch {
            // The save never happened, so the picker must not keep showing the
            // selection that failed.
            model.pickerSelection = restoreSelection
            model.present(error, title: "Couldn't update apps")
        }
    }
}
