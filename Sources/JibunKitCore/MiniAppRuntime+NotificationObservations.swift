import Foundation

public extension MiniAppRuntime {
    /// Creates a NotificationCenter ownership scope whose registrations are
    /// cancelled as part of this runtime's awaited shutdown.
    func makeNotificationObservations() throws -> MiniAppNotificationObservations {
        let observations = MiniAppNotificationObservations()
        try onShutdown { observations.cancelAll() }
        return observations
    }
}
