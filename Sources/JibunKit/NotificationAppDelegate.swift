#if os(iOS)
import JibunKitCore
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
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler([.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let candidate = MiniAppNotificationRoute.candidateRoute(
            userInfo: response.notification.request.content.userInfo
        )
        // UIKit performs snapshot/state restoration work from this callback.
        // The synthesized async delegate thunk can complete on a cooperative
        // executor, causing UIKit's main-thread assertion on notification taps.
        Task { @MainActor in
            // AppNavigation also rejects IDs absent from the registry.
            AppNavigation.shared.openNotificationRoute(candidate)
            completionHandler()
        }
    }
}
#endif
