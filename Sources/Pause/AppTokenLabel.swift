import FamilyControls
import ManagedSettings
import SwiftUI

struct AppTokenLabel: View {
    let applicationToken: ApplicationToken

    var body: some View {
        Label(applicationToken)
    }
}
