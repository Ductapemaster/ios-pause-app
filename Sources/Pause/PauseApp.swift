import SwiftUI

@main
struct PauseApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                switch model.rootRoute {
                case .configurationRepair:
                    RepairView(
                        content: model.configurationSafetyRepairContent,
                        onDismiss: nil,
                        onResetRuntime: nil
                    )
                case .authorizedContent:
                    authorizedContent
                case .authorization:
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
                switch phase {
                case .active:
                    model.sceneDidBecomeActive()
                case .background:
                    model.sceneDidLeaveForeground()
                case .inactive:
                    // A banner, a Control Center pull, or the app switcher. The
                    // user has not left, so an in-progress countdown stands.
                    // Backgrounding still arrives as its own phase.
                    break
                @unknown default:
                    break
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
                onUseSession: model.requestSessionGrant,
                onCancel: model.returnToConfiguration
            )
        case let .manualReturn(content):
            ManualReturnView(content: content)
        case let .refused(content):
            RefusalView(content: content, onDismiss: model.returnToConfiguration)
        case let .repair(content):
            RepairView(
                content: content,
                onDismiss: model.returnToConfiguration,
                onResetRuntime: { model.resetRuntime(ruleID: $0) }
            )
        }
    }
}
