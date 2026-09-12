#if os(iOS)
import JibunKitCore
import UserNotifications

public enum ReminderScheduleResult {
    case scheduled
    case denied
}

public struct ReminderNotificationScheduler: Sendable {
    public static let permission = MiniAppPermissionDeclaration(
        id: "notifications", title: "通知", purpose: "保存したメッセージを指定時刻に通知します。",
        deniedBehavior: "メッセージの保存と閲覧は引き続き利用できます。")
    private let context: MiniAppContext

    public init(context: MiniAppContext) {
        self.context = context
    }

    public func schedule(message: String) async throws -> ReminderScheduleResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        try Task.checkCancellation()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return .denied }
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return .denied
        }

        let content = UNMutableNotificationContent()
        content.title = "リマインダー"
        content.body = message
        content.sound = .default
        content.userInfo = context.notificationUserInfo

        let request = UNNotificationRequest(
            identifier: context.notificationRequestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        try Task.checkCancellation()
        try await center.add(request)
        return .scheduled
    }
}
#endif
