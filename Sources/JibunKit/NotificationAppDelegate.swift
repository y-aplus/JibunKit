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
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let registeredIDs = await MiniAppRegistry.registeredIDs
        let miniAppID = MiniAppNotificationRoute.resolve(
            userInfo: response.notification.request.content.userInfo,
            registeredIDs: registeredIDs
        )
        await AppNavigation.shared.openNotificationTarget(miniAppID)
    }
}
#endif
