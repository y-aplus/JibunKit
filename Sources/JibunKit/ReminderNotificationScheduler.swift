#if os(iOS)
import JibunKitCore
import UserNotifications

enum ReminderScheduleResult {
    case scheduled
    case denied
}

struct ReminderNotificationScheduler {
    func schedule(message: String) async throws -> ReminderScheduleResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

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
        content.userInfo = [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: MiniAppID.reminder.rawValue,
        ]

        let request = UNNotificationRequest(
            identifier: MiniAppID.reminder.notificationRequestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )
        try await center.add(request)
        return .scheduled
    }
}
#endif
