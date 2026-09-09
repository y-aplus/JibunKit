/// Selects only one owner's requests, including the legacy single request ID.
/// The supplied IDs are a snapshot; this is not an atomic stop of new scheduling.
public struct MiniAppNotificationRemoval: Sendable, Equatable {
    public let pending: [String]
    public let delivered: [String]

    public init(context: MiniAppContext, pending: [String], delivered: [String]) {
        self.pending = pending.filter(context.ownsNotificationRequestIdentifier)
        self.delivered = delivered.filter(context.ownsNotificationRequestIdentifier)
    }
}

#if canImport(UserNotifications)
import UserNotifications

public extension MiniAppContext {
    /// Removes this Feature's pending and delivered notifications. Coordinate
    /// concurrent scheduling in the Feature runtime when an empty set is needed.
    func removeAllOwnedNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let removal = MiniAppNotificationRemoval(context: self,
            pending: pending.map(\.identifier), delivered: delivered.map { $0.request.identifier })
        center.removePendingNotificationRequests(withIdentifiers: removal.pending)
        center.removeDeliveredNotifications(withIdentifiers: removal.delivered)
    }
}
#endif
