import SwiftUI

struct RepairView: View {
    let content: RepairContent
    let onDismiss: (() -> Void)?
    let onResetRuntime: ((UUID) -> Void)?
    @State private var isResetConfirmationPresented = false

    init(
        content: RepairContent,
        onDismiss: (() -> Void)?,
        onResetRuntime: ((UUID) -> Void)? = nil
    ) {
        self.content = content
        self.onDismiss = onDismiss
        self.onResetRuntime = onResetRuntime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let applicationToken = content.applicationToken {
                AppTokenLabel(applicationToken: applicationToken)
                    .font(.title2.weight(.semibold))
            }

            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text(content.title)
                .font(.title.bold())

            Text(content.message)
                .foregroundStyle(.secondary)

            if content.runtimeResetRuleID != nil, onResetRuntime != nil {
                Button("Reset this app’s runtime", role: .destructive) {
                    isResetConfirmationPresented = true
                }
                .buttonStyle(.borderedProminent)
            }

            if content.runtimeResetRuleID == nil, let onDismiss {
                Button("Back to app list", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Pause")
        .navigationBarBackButtonHidden()
        .confirmationDialog(
            "Reset this app’s runtime?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let ruleID = content.runtimeResetRuleID, let onResetRuntime {
                Button("Reset this app’s runtime", role: .destructive) {
                    onResetRuntime(ruleID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can reset today’s session count for this app. No other app will be changed.")
        }
    }
}
