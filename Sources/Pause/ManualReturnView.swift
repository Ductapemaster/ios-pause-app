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
        VStack(spacing: 20) {
            AppIdentityBadge(applicationToken: content.applicationToken)

            PulsingCircles(isAnimated: false) {
                ZStack {
                    Circle()
                        .fill(Color.pauseTint)
                        .frame(width: 88, height: 88)

                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxHeight: .infinity)

            Text("Session ready")
                .font(.title.bold())

            Text("Your session is ready. Return to the app from the Home Screen or App Switcher.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            Text("Ends at \(content.expiresAt.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}
