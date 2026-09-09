#if os(iOS)
import SwiftUI
import JibunKitCore

@main
struct JibunKitApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate
    @State private var navigation = AppNavigation.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifecycle = MiniAppLifecycleDispatcher(
        handlers: MiniAppRegistry.all.compactMap(\.onHostPhaseChange)
    )

    var body: some Scene {
        WindowGroup {
            MiniAppListScreen(navigation: navigation)
                .onOpenURL { navigation.openURL($0) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: lifecycle.update(.active)
            case .inactive: lifecycle.update(.inactive)
            case .background: lifecycle.update(.background)
            @unknown default: break
            }
        }
    }
}
#endif
