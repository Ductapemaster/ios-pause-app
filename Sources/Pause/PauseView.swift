import ManagedSettings
import PauseCore
import SwiftUI

struct PauseView: View {
    let entry: PauseEntryContext
    let isGrantRequested: Bool
    let onUseSession: () -> Void
    let onCancel: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            AppIdentityBadge(applicationToken: entry.applicationToken)

            Text(sessionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PulsingCircles {
                VStack(spacing: 6) {
                    Text(remainingSeconds, format: .number)
                        .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(remainingSeconds) seconds remaining")

                    Text("Take a pause")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            Text("Stay in Pause until the countdown finishes. Leaving cancels this attempt.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            Button {
                onUseSession()
            } label: {
                if isGrantRequested {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Use session")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!entry.countdown.isComplete(at: now) || isGrantRequested)

            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isGrantRequested)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onReceive(timer) { date in
            now = date
        }
    }

    private var sessionSummary: String {
        let minutes = entry.details.lengthMinutes
        let unit = minutes == 1 ? "minute" : "minutes"
        return "Session \(entry.details.sessionNumber) of \(entry.details.sessionsPerDay) · \(minutes) \(unit)"
    }

    private var remainingSeconds: Int {
        entry.countdown.remainingSeconds(at: now)
    }
}

struct RefusalView: View {
    let content: RefusalContent
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AppTokenLabel(applicationToken: content.applicationToken)
                .font(.title2.weight(.semibold))

            Text(content.title)
                .font(.title.bold())

            Text(content.message)
                .foregroundStyle(.secondary)

            Button("Back to app list", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Pause")
        .navigationBarBackButtonHidden()
    }
}
