#if canImport(UserNotifications)
import Foundation
import UserNotifications
import RecordsFeature
import JibunKitCore

public enum RecordsNotifications {
    public enum Failure: LocalizedError {
        case invalidDate, denied
        public var errorDescription: String? {
            switch self {
            case .invalidDate: "未来の日時を指定してください。"
            case .denied: "通知が許可されていません。設定アプリで通知を許可してください。"
            }
        }
    }

    private static let context = MiniAppContext(id: MiniAppID("records"))

    /// Restoration replaces the data, not OS reservations. Never clear another
    /// Feature's notifications, including the legacy Reminder request.
    public static func clearReminders() async {
        await context.removeAllOwnedNotifications()
    }

    public static func request(for record: Record, at date: Date, now: Date = Date()) throws -> UNNotificationRequest {
        let interval = date.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { throw Failure.invalidDate }
        let content = UNMutableNotificationContent()
        content.title = record.title
        content.body = "記録を確認する時刻です。"
        content.sound = .default
        content.userInfo = context.notificationUserInfo(destination: record.id.uuidString)!
        return UNNotificationRequest(identifier: context.notificationRequestIdentifier(for: record.id.uuidString),
                                     content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    public static let actions = RecordReminderActions(schedule: { record, date in
        // Reject invalid input before asking for permission, then recalculate the
        // delay after the user responds so the requested wall-clock time is kept.
        _ = try request(for: record, at: date)
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw Failure.denied }
        try await center.add(request(for: record, at: date))
    }, cancel: { id in
        let identifier = context.notificationRequestIdentifier(for: id.uuidString)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    })
}
#endif
