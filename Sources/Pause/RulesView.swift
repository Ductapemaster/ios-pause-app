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
            NewAppSetupSheet(
                addedApplicationTokens: addition.addedApplicationTokens,
                alreadyCoveredApplicationTokens: addition.alreadyCoveredApplicationTokens
            ) { allowances in
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
            Section("Apps") {
                ForEach(model.configuration.rules) { rule in
                    if let target = model.configuration.targets.first(where: { $0.ruleID == rule.id }) {
                        NavigationLink {
                            RuleEditorView(
                                model: model,
                                rule: rule,
                                applicationToken: target.applicationToken
                            )
                        } label: {
                            HStack {
                                AppTokenLabel(applicationToken: target.applicationToken)

                                if let kind = model.pendingChange(forRuleID: rule.id)?.kind {
                                    Image(systemName: kind.symbolName)
                                        .foregroundStyle(kind.tint)
                                        .accessibilityLabel(kind.accessibilityLabel)
                                }

                                Spacer()
                                Text(usageText(for: rule))
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Stepper(value: pauseSeconds, in: 1...120) {
                    LabeledContent {
                        Text("\(model.configuration.settings.pauseSeconds) sec")
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    } label: {
                        HStack {
                            Text("Pause duration")
                            if model.pendingSettingsChange() != nil {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Allowance changing")
                            }
                        }
                    }
                }
                .disabled(model.pendingSettingsChange() != nil)

                Picker(selection: resetMinuteOfDay) {
                    ForEach(Array(stride(from: 0, through: 1425, by: 15)), id: \.self) { minute in
                        Text(Self.resetLabel(for: minute)).tag(minute)
                    }
                } label: {
                    Text("Day reset")
                }
                // Settings are judged as one unit: a save that only moves the
                // reset still rebuilds `candidate.settings` from the in-force
                // pause duration, and the router reads that whole unit as
                // touched, discarding a pending shorter pause. Locking this
                // picker alongside the stepper is what keeps a pending change
                // from being overwritten by an edit to its neighbor.
                .disabled(model.pendingSettingsChange() != nil)
            } footer: {
                if let change = model.pendingSettingsChange(), let file = model.configurationFile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ScheduledChangeWording.settingsDescription(of: change, in: file))
                        Button("Cancel change") {
                            model.cancelScheduledSettingsChange()
                        }
                    }
                } else {
                    Text("The pause shown before every allowed session, and the time each day's sessions renew.")
                }
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

    /// A picker save, held while the user is shown what it means: apps already
    /// covered are named, and apps genuinely being added each get an allowance.
    /// The whole selection is carried along so the save that finally runs is
    /// the one the user pressed Save on.
    private struct PendingAddition: Identifiable {
        let id = UUID()
        let selection: FamilyActivitySelection
        let addedApplicationTokens: [ApplicationToken]
        let alreadyCoveredApplicationTokens: [ApplicationToken]
    }

    /// Routes a saved picker selection. The picker is add-only, so an empty
    /// selection means nothing was picked and there is nothing to do. Anything
    /// else opens the setup sheet: apps already covered are named there,
    /// apps genuinely being added each get an allowance, and the save itself
    /// only happens when the sheet reports something to add — a selection that
    /// names only already-covered apps closes the sheet without writing
    /// anything.
    private func savePickerSelection(_ selection: FamilyActivitySelection) {
        guard !selection.applicationTokens.isEmpty else { return }
        let (added, alreadyCovered) = model.classifyPickerSelection(selection)
        pendingAddition = PendingAddition(
            selection: selection,
            addedApplicationTokens: added,
            alreadyCoveredApplicationTokens: alreadyCovered
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
