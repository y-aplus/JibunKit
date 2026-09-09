#if canImport(UserNotifications)
import UserNotifications

public struct MiniAppForegroundNotification: Sendable, Equatable {
    public let requestIdentifier: String
    public let categoryIdentifier: String
    public let destination: String?

    public init(requestIdentifier: String, categoryIdentifier: String, destination: String?) {
        self.requestIdentifier = requestIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.destination = destination
    }
}

@MainActor
public enum MiniAppNotificationPresentation {
    /// Consult only the notification owner. An empty option set intentionally silences it.
    /// Missing policies retain the host's existing presentation behavior.
    public static func options(
        for notification: MiniAppForegroundNotification,
        route: MiniAppRoute?,
        policyForOwner: (MiniAppID) -> (@MainActor (MiniAppForegroundNotification) -> UNNotificationPresentationOptions)?
    ) -> UNNotificationPresentationOptions {
        guard let route, let policy = policyForOwner(route.id) else { return [.banner, .list, .sound] }
        return policy(notification)
    }
}
#endif
