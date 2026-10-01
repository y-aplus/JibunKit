import JibunKitCore
import UserNotifications

/// Built only when `EnabledFeatureBuildRequirements.notificationService` is set.
/// Add each participating Feature's handler here, and its package product to
/// this extension target in Project.swift.
final class NotificationService: MiniAppNotificationService {
    override func makeHandlers() -> [MiniAppID: any MiniAppNotificationServiceHandling] {
        [:]
    }
}
