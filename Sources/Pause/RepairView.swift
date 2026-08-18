import SwiftUI

struct RepairView: View {
    let content: RepairContent
    let onDismiss: () -> Void

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

            Button("Back to app list", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Pause")
        .navigationBarBackButtonHidden()
    }
}
