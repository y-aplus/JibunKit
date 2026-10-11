#if os(iOS)
import JibunKitCore
import UserNotifications

public enum ReminderScheduleResult {
    case scheduled
    case denied
}

public struct ReminderNotificationScheduler: Sendable {
    public static let permission = MiniAppPermissionDeclaration(
        id: "notifications", title: String(localized: "Notifications", bundle: .module),
        purpose: String(localized: "Notifies you of the saved message at the set time.", bundle: .module),
        deniedBehavior: String(localized: "You can still save and view the message.", bundle: .module))
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
            let granted = try await center.requestAuthorization(options: Self.authorizationOptions)
            guard granted else { return .denied }
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            // Installations that allowed notifications before the badge was
            // added asked only for alerts and sounds. Ask again with the
            // badge; iOS decides whether to show anything.
            if settings.badgeSetting == .notSupported {
                _ = try? await center.requestAuthorization(options: Self.authorizationOptions)
            }
        @unknown default:
            return .denied
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Reminder", bundle: .module)
        content.body = message
        content.sound = .default
        content.userInfo = context.notificationUserInfo
        content.filterCriteria = context.notificationFilterCriteria

        let request = UNNotificationRequest(
            identifier: context.notificationRequestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.delay, repeats: false)
        )
        try Task.checkCancellation()
        try await center.add(request)
        return .scheduled
    }

    /// Shows the number of reminders that are scheduled and not yet delivered
    /// as this Feature's share of the app icon badge. The count changes only
    /// while JibunKit runs, so a reminder delivered in the background clears
    /// its count the next time Reminder opens.
    @MainActor
    public func refreshBadge() async throws {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { context.ownsNotificationRequestIdentifier($0.identifier) }.count
        try await context.setBadgeCount(pending)
    }

    /// Seconds from scheduling to delivery.
    public static let delay: TimeInterval = 10

    /// The badge needs its own authorization option; without it the icon
    /// shows no number even when the count is set.
    static let authorizationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
}
#endif
