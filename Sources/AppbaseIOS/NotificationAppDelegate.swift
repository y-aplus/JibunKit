#if os(iOS)
import AppbaseCore
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
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let miniAppID = MiniAppNotificationRoute.resolve(
            userInfo: response.notification.request.content.userInfo
        )
        await AppNavigation.shared.openNotificationTarget(miniAppID)
    }
}
#endif
