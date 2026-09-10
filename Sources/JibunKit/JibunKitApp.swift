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
    @State private var activity = MiniAppSceneActivityDispatcher(
        handlers: MiniAppRegistry.all.compactMap { definition in
            definition.onSceneActivityChange.map { (definition.id, $0) }
        }
    )
    @Environment(\.scenePhase) private var scenePhase

    private var activityPhase: MiniAppSceneActivity.Phase {
        switch scenePhase {
        case .active: .active
        case .background: .background
        default: .inactive
        }
    }

    var body: some View {
        MiniAppListScreen(navigation: navigation)
            // SwiftUI delivers this URL to a particular scene; keep that target.
            .onOpenURL { navigation.openURL($0) }
            .onAppear {
                activity.connect(phase: activityPhase, selectedID: navigation.activeID)
                guard registration == nil else { return }
                registration = AppSceneRouting.shared.register(isActive: scenePhase == .active) { [weak navigation] route in
                    navigation?.openNotificationRoute(route)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                activity.update(phase: activityPhase, selectedID: navigation.activeID)
                if let registration { AppSceneRouting.shared.update(registration, isActive: phase == .active) }
            }
            .onChange(of: navigation.activeID) { _, selectedID in
                activity.update(phase: activityPhase, selectedID: selectedID)
            }
            .onDisappear {
                activity.disconnect()
                if let registration { AppSceneRouting.shared.unregister(registration) }
                registration = nil
            }
    }
}
#endif
