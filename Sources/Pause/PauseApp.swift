import SwiftUI

@main
struct PauseApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if model.requiresConfigurationRepair {
                    RepairView(
                        content: model.configurationSafetyRepairContent,
                        onDismiss: nil
                    )
                } else if model.hasScreenTimeAuthorization {
                    authorizedContent
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
                if phase == .active {
                    model.sceneDidBecomeActive()
                } else {
                    model.sceneDidBecomeInactive()
                }
            }
            .task {
                guard scenePhase == .active else { return }
                model.sceneDidBecomeActive()
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        switch model.entryRoute {
        case .configuration:
            RulesView(model: model)
        case let .pause(entry):
            PauseView(
                entry: entry,
                isGrantRequested: model.isGrantRequested,
                onUseSession: model.requestSessionGrant
            )
        case let .refused(content):
            RefusalView(content: content, onDismiss: model.returnToConfiguration)
        case let .repair(content):
            RepairView(content: content, onDismiss: model.returnToConfiguration)
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
