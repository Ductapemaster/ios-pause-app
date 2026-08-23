import ManagedSettings
import PauseCore
import SwiftUI

/// Collects an allowance for each newly picked app before any of them is
/// written.
///
/// Adding an app is the one moment its allowance can be set freely: a brand new
/// rule is compared against no previous rule, so any values take effect the
/// same day, while raising them afterwards is a loosening that waits for the
/// next reset. A default the user never saw would therefore stand until
/// tomorrow.
///
/// Several apps are configured in turn rather than refused, and nothing reaches
/// disk until the last one is confirmed — so backing out part-way leaves Pause
/// exactly as it was, with no half-added app.
struct NewAppSetupSheet: View {
    let applicationTokens: [ApplicationToken]
    let onComplete: ([ApplicationToken: AppRule.Allowance]) -> Void

    @State private var stepIndex = 0
    @State private var chosen: [ApplicationToken: AppRule.Allowance] = [:]
    @State private var sessionsPerDay = AppRuleLimits.defaultSessionsPerDay
    @State private var sessionLengthMinutes = AppRuleLimits.defaultSessionLengthMinutes
    @Environment(\.dismiss) private var dismiss

    private var currentToken: ApplicationToken? {
        applicationTokens.indices.contains(stepIndex) ? applicationTokens[stepIndex] : nil
    }

    private var isLastStep: Bool {
        stepIndex == applicationTokens.count - 1
    }

    var body: some View {
        NavigationStack {
            Form {
                if let currentToken {
                    Section {
                        AppTokenLabel(applicationToken: currentToken)
                    }
                }

                AllowanceSection(
                    sessionsPerDay: $sessionsPerDay,
                    sessionLengthMinutes: $sessionLengthMinutes,
                    footer: "These take effect as soon as the app is added."
                )
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLastStep ? "Add" : "Next") { advance() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var title: String {
        guard applicationTokens.count > 1 else { return "Add app" }
        return "App \(stepIndex + 1) of \(applicationTokens.count)"
    }

    private func advance() {
        guard let currentToken else { return }
        chosen[currentToken] = AppRule.Allowance(
            sessionsPerDay: sessionsPerDay,
            sessionLengthMinutes: sessionLengthMinutes
        )

        guard isLastStep else {
            stepIndex += 1
            sessionsPerDay = AppRuleLimits.defaultSessionsPerDay
            sessionLengthMinutes = AppRuleLimits.defaultSessionLengthMinutes
            return
        }

        let completed = chosen
        dismiss()
        onComplete(completed)
    }
}
