#if os(iOS)
import JibunKitCore
import OSLog
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
        do {
            let registrations = Dictionary(uniqueKeysWithValues:
                MiniAppRegistry.all.map { ($0.id, $0.notificationCategories) })
            let categories = try MiniAppNotificationCategories.merged(registrations)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        } catch {
            preconditionFailure("Invalid Feature notification category registration: \(error)")
        }
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let route = MiniAppNotificationRoute.candidateRoute(userInfo: notification.request.content.userInfo)
        let event = MiniAppForegroundNotification(requestIdentifier: notification.request.identifier,
            categoryIdentifier: notification.request.content.categoryIdentifier, destination: route?.destination)
        Task { @MainActor in
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
            userText: (response as? UNTextInputNotificationResponse)?.userText
        )
        // UIKit performs snapshot/state restoration work from this callback.
        // The synthesized async delegate thunk can complete on a cooperative
        // executor, causing UIKit's main-thread assertion on notification taps.
        Task { @MainActor in
            defer { completionHandler() }
            // Opening preserves the legacy route behavior. Dismiss/custom actions
            // must not navigate or disturb another Feature's visible screen.
            await MiniAppNotificationActionDelivery.deliver(action, route: candidate,
                handlerForOwner: { MiniAppRegistry.definition(for: $0)?.onNotificationAction },
                open: { AppNavigation.shared.openNotificationRoute($0) })
            Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
                .notice("Notification route dispatched; parsed route: \(candidate != nil)")
        }
    }
}
#endif
