import SwiftUI

@main
struct PauseApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if model.hasScreenTimeAuthorization {
                    RulesView(model: model)
                } else {
                    AuthorizationView(model: model)
                }
            }
            .tint(Color(red: 0.36, green: 0.36, blue: 0.84))
            .alert(item: $model.presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                model.refreshAuthorizationStatus()
            }
        }
    }
}

private extension AppModel {
    var hasScreenTimeAuthorization: Bool {
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}
