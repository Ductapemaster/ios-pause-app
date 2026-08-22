import FamilyControls
import SwiftUI

struct AuthorizationView: View {
    @ObservedObject var model: AppModel
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screen Time access")
                .font(.title.bold())

            Text(explanation)
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                isRequesting = true
                Task {
                    await model.requestAuthorization()
                    isRequesting = false
                }
            } label: {
                HStack {
                    Spacer()
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("Allow Screen Time access")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Pause")
    }

    private var explanation: String {
        if model.authorizationStatus == .denied {
            return "Pause needs Screen Time access to let you choose apps and apply their limits. Access is currently denied."
        }
        return "Pause uses Screen Time access to let you choose apps and apply the allowances you set."
    }
}
