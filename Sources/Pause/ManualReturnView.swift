import ManagedSettings
import SwiftUI

struct ManualReturnContent {
    let ruleID: UUID
    let applicationToken: ApplicationToken
    let expiresAt: Date
}

struct ManualReturnView: View {
    let content: ManualReturnContent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AppTokenLabel(applicationToken: content.applicationToken)
                .font(.title2.weight(.semibold))

            Text("Session ready")
                .font(.title.bold())

            Text("Your session is ready. Return to the app from the Home Screen or App Switcher.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Pause")
        .navigationBarBackButtonHidden()
    }
}
