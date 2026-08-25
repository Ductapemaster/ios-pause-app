import FamilyControls
import ManagedSettings
import SwiftUI

struct AppTokenLabel: View {
    let applicationToken: ApplicationToken

    var body: some View {
        Label(applicationToken)
    }
}

/// The app being entered, presented as its own subject: icon over name,
/// centred. `Label(applicationToken)` lays out greedily, so both copies are
/// sized to their content rather than left to fill the column.
struct AppIdentityBadge: View {
    let applicationToken: ApplicationToken

    var body: some View {
        VStack(spacing: 10) {
            AppTokenLabel(applicationToken: applicationToken)
                .labelStyle(.iconOnly)
                .frame(width: 56, height: 56)

            AppTokenLabel(applicationToken: applicationToken)
                .labelStyle(.titleOnly)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
