import ManagedSettings
import PauseCore
import SwiftUI

/// Reports the picker's tap and collects an allowance for each newly picked
/// app before any of them is written.
///
/// The picker is add-only, so a saved selection can name apps already covered
/// alongside apps genuinely being added. Apps already covered get a leading
/// notice step naming them, so a pick that quietly did nothing for them is not
/// left to be inferred from a shorter list of screens. Apps being added each
/// get their own allowance step.
///
/// Adding an app is the one moment its allowance can be set freely: a brand new
/// rule is compared against no previous rule, so any values take effect the
/// same day, while raising them afterwards is a loosening that waits for the
/// next reset. A default the user never saw would therefore stand until
/// tomorrow.
///
/// Several apps are configured in turn rather than refused, and nothing reaches
/// disk until the last one is confirmed — so backing out part-way leaves Pause
/// exactly as it was, with no half-added app. When every pick is already
/// covered there is nothing to add, and `onComplete` is never called: the
/// notice step is the whole sheet, and dismissing it writes nothing.
struct NewAppSetupSheet: View {
    let addedApplicationTokens: [ApplicationToken]
    let alreadyCoveredApplicationTokens: [ApplicationToken]
    let onComplete: ([ApplicationToken: AppRule.Allowance]) -> Void

    @State private var stepIndex = 0
    @State private var chosen: [ApplicationToken: AppRule.Allowance] = [:]
    @State private var sessionsPerDay = AppRuleLimits.defaultSessionsPerDay
    @State private var sessionLengthMinutes = AppRuleLimits.defaultSessionLengthMinutes
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case notice
        case allowance(ApplicationToken)
    }

    private var hasNoticeStep: Bool {
        !alreadyCoveredApplicationTokens.isEmpty
    }

    private var steps: [Step] {
        var result: [Step] = []
        if hasNoticeStep {
            result.append(.notice)
        }
        result.append(contentsOf: addedApplicationTokens.map(Step.allowance))
        return result
    }

    private var currentStep: Step? {
        let steps = steps
        return steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    private var isLastStep: Bool {
        stepIndex == steps.count - 1
    }

    var body: some View {
        NavigationStack {
            Form {
                switch currentStep {
                case .notice:
                    Section("Already in Pause") {
                        ForEach(alreadyCoveredApplicationTokens, id: \.self) { token in
                            AppTokenLabel(applicationToken: token)
                                // The label draws its app out of process from an
                                // opaque token. Left at one identity across steps
                                // SwiftUI reuses the view, and it keeps showing the
                                // app it drew first; keying it to the token makes
                                // each row build a label of its own.
                                .id(token)
                        }
                    }
                case let .allowance(token):
                    Section {
                        AppTokenLabel(applicationToken: token)
                            // Same hazard as above: keyed per step so SwiftUI
                            // doesn't reuse the label across steps.
                            .id(token)
                    }

                    AllowanceSection(
                        sessionsPerDay: $sessionsPerDay,
                        sessionLengthMinutes: $sessionLengthMinutes,
                        footer: "These take effect as soon as the app is added."
                    )
                case nil:
                    EmptyView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle) { advance() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch currentStep {
        case .notice:
            return alreadyCoveredApplicationTokens.count > 1 ? "Already in Pause" : "Already added"
        case let .allowance(token):
            guard addedApplicationTokens.count > 1 else { return "Add app" }
            let index = addedApplicationTokens.firstIndex(of: token) ?? 0
            return "App \(index + 1) of \(addedApplicationTokens.count)"
        case nil:
            return ""
        }
    }

    private var confirmationTitle: String {
        guard isLastStep else { return "Next" }
        return addedApplicationTokens.isEmpty ? "Done" : "Add"
    }

    private func advance() {
        if case let .allowance(token) = currentStep {
            chosen[token] = AppRule.Allowance(
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            )
        }

        guard isLastStep else {
            stepIndex += 1
            sessionsPerDay = AppRuleLimits.defaultSessionsPerDay
            sessionLengthMinutes = AppRuleLimits.defaultSessionLengthMinutes
            return
        }

        let completed = chosen
        dismiss()
        // Nothing was added, so there is nothing to write: the notice step was
        // the whole sheet.
        guard !addedApplicationTokens.isEmpty else { return }
        onComplete(completed)
    }
}
