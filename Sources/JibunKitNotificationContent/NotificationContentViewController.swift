import JibunKitCore
import UIKit
import UserNotifications
import UserNotificationsUI

/// Built only when `EnabledFeatureBuildRequirements.notificationContent` is set.
/// Return each participating Feature's controller, and add its package product
/// to this extension target in Project.swift.
final class NotificationContentViewController: MiniAppNotificationContentViewController {
    override var owners: [MiniAppID] { [] }

    override func makeContentViewController(for owner: MiniAppID) -> (UIViewController & UNNotificationContentExtension)? {
        nil
    }
}
