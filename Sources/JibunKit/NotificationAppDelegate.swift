#if os(iOS)
import JibunKitCore
import OSLog
import TipKit
import UIKit
import UserNotifications

@MainActor
final class NotificationAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Apply persisted admission before passive cold-launch registrations.
        // Registration rejection must not turn a fallible OS operation into an
        // app-wide trap. Keep the failed owner visible with its launch error.
        _ = MiniAppRegistry.management
        MiniAppRegistry.launchState.register(MiniAppRegistry.all)
        do {
            let registrations = Dictionary(uniqueKeysWithValues:
                MiniAppRegistry.all.map { ($0.id,
                    MiniAppRegistry.management.isEnabled($0.id) && MiniAppRegistry.launchState.errors[$0.id] == nil
                        ? $0.notificationCategories : []) })
            try MiniAppNotificationCategoryRegistry.shared.configure(registrations)
        } catch {
            MiniAppRegistry.launchState.hostError = String(describing: error)
            Logger(subsystem: "com.jibunkit.app", category: "Launch")
                .error("Notification registration failed: \(String(describing: error))")
        }
        // TipKit allows one configuration per process. The host owns it so
        // Features only declare tips; a Feature must never call configure.
        do { try Tips.configure() } catch {
            Logger(subsystem: "com.jibunkit.app", category: "Launch")
                .error("TipKit configuration failed: \(String(describing: error))")
        }
        MiniAppRegistry.reconcileContinuingSurfaces()
        MiniAppRegistry.refreshQuickActions()
        MiniAppRegistry.refreshBadge()
        // Explicit build-time opt-in. It does not replace a valid aps-environment
        // entitlement/profile. Registration failures still reach the coordinator.
        if Bundle.main.object(forInfoDictionaryKey: "JibunKitRemotePushEnabled") as? Bool == true {
            application.registerForRemoteNotifications()
        }
        return true
    }

    /// A cold launch from a quick action carries the item here; a running app
    /// receives it through the scene delegate. Both use the scene router.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { MiniAppRegistry.performQuickAction(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = MiniAppWindowSceneDelegate.self
        }
        return configuration
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MiniAppRemotePushCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MiniAppRemotePushCoordinator.shared.didFailToRegisterForRemoteNotifications(error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            guard let route = MiniAppNotificationRoute.candidateRoute(userInfo: userInfo),
                  MiniAppRegistry.management.isEnabled(route.id),
                  MiniAppRegistry.launchState.errors[route.id] == nil else {
                completionHandler(.noData)
                return
            }
            let result = await MiniAppRemotePushCoordinator.shared.deliver(userInfo: userInfo)
            switch result {
            case .newData: completionHandler(.newData)
            case .noData: completionHandler(.noData)
            case .failed: completionHandler(.failed)
            }
        }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let route = MiniAppNotificationRoute.candidateRoute(userInfo: notification.request.content.userInfo)
        let event = MiniAppForegroundNotification(requestIdentifier: notification.request.identifier,
            categoryIdentifier: notification.request.content.categoryIdentifier, destination: route?.destination,
            requestSnapshot: Self.snapshot(notification.request))
        Task { @MainActor in
            if let route, !MiniAppRegistry.management.isEnabled(route.id) {
                completionHandler([])
                return
            }
            completionHandler(MiniAppNotificationPresentation.options(for: event, route: route,
                policyForOwner: { MiniAppRegistry.definition(for: $0)?.notificationPresentation }))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
            .notice("Notification response received")
        let candidate = MiniAppNotificationRoute.candidateRoute(
            userInfo: response.notification.request.content.userInfo
        )
        let kind: MiniAppNotificationAction.Kind
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: kind = .open
        case UNNotificationDismissActionIdentifier: kind = .dismiss
        default: kind = .custom(response.actionIdentifier)
        }
        let action = MiniAppNotificationAction(
            kind: kind,
            requestIdentifier: response.notification.request.identifier,
            destination: candidate?.destination,
            userText: (response as? UNTextInputNotificationResponse)?.userText,
            requestSnapshot: Self.snapshot(response.notification.request)
        )
        // UIKit performs snapshot/state restoration work from this callback.
        // The synthesized async delegate thunk can complete on a cooperative
        // executor, causing UIKit's main-thread assertion on notification taps.
        Task { @MainActor in
            defer { completionHandler() }
            if let candidate, !MiniAppRegistry.management.isEnabled(candidate.id) { return }
            // Opening preserves the legacy route behavior. Dismiss/custom actions
            // must not navigate or disturb another Feature's visible screen.
            await MiniAppNotificationActionDelivery.deliver(action, route: candidate,
                handlerForOwner: { MiniAppRegistry.definition(for: $0)?.onNotificationAction },
                open: { AppSceneRouting.shared.open($0) })
            Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
                .notice("Notification route dispatched; parsed route: \(candidate != nil)")
        }
    }

    nonisolated private static func snapshot(_ request: UNNotificationRequest) -> MiniAppNotificationRequestSnapshot? {
        do { return try MiniAppNotificationRequestSnapshot(request: request) }
        catch {
            // A snapshot failure must not suppress legacy navigation or completion.
            Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
                .error("Unable to snapshot native notification request: \(String(describing: error))")
            return nil
        }
    }
}

/// SwiftUI keeps owning the window; this delegate only receives quick actions
/// while the app is running.
@MainActor
final class MiniAppWindowSceneDelegate: NSObject, UIWindowSceneDelegate {
    // The async form avoids depending on the SDK's completion-handler annotations,
    // which would otherwise silently stop matching this optional requirement.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        MiniAppRegistry.performQuickAction(shortcutItem)
    }
}
#endif
