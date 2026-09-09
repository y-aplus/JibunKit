import Foundation

/// Optional system integration supplied by the standalone app or host adapter.
public struct RecordReminderActions: Sendable {
    public let schedule: @Sendable (Record, Date) async throws -> Void
    public let cancel: @Sendable (UUID) async throws -> Void

    public init(schedule: @escaping @Sendable (Record, Date) async throws -> Void,
                cancel: @escaping @Sendable (UUID) async throws -> Void) {
        self.schedule = schedule
        self.cancel = cancel
    }
}
