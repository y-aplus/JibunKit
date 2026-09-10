#if os(iOS)
import SwiftUI
import JibunKitCore

@main
struct JibunKitApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifecycle = MiniAppLifecycleDispatcher(
        handlers: MiniAppRegistry.all.compactMap(\.onHostPhaseChange)
    )

    var body: some Scene {
        WindowGroup {
            MiniAppSceneRoot()
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

/// State is instantiated inside WindowGroup's view hierarchy, once per window.
private struct MiniAppSceneRoot: View {
    @State private var navigation = AppNavigation()
    @State private var registration: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MiniAppListScreen(navigation: navigation)
            // SwiftUI delivers this URL to a particular scene; keep that target.
            .onOpenURL { navigation.openURL($0) }
            .onAppear {
                guard registration == nil else { return }
                registration = AppSceneRouting.shared.register(isActive: scenePhase == .active) { [weak navigation] route in
                    navigation?.openNotificationRoute(route)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if let registration { AppSceneRouting.shared.update(registration, isActive: phase == .active) }
            }
            .onDisappear {
                if let registration { AppSceneRouting.shared.unregister(registration) }
                registration = nil
            }
    }
}
#endif
