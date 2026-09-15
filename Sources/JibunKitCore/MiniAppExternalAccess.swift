import Foundation

/// Optional admission shared with extension processes. The Feature owns the
/// actual interprocess mechanism; callbacks must not merely toggle an NSLock
/// or read a point-in-time preference. Closing waits for admitted writes.
public struct MiniAppExternalAccess: Sendable {
    public let id: MiniAppID
    /// Bootstrap before host entry. Never silently reopen interrupted work.
    public let prepare: @Sendable (Bool) throws -> Void
    public let close: @Sendable () async throws -> Void
    /// Called under the host's exclusive reservation, after enable preparation.
    /// May explicitly recover abandoned maintenance after disable/re-enable.
    public let open: @Sendable () async throws -> Void
    /// Enclose the Feature lifecycle; stop/failed-stop/resume must preserve
    /// management's independent admission decision throughout restoration.
    public let restoreLifecycle: @Sendable (MiniAppRestoreLifecycle?) -> MiniAppRestoreLifecycle

    public init(id: MiniAppID,
                prepare: @escaping @Sendable (Bool) throws -> Void,
                close: @escaping @Sendable () async throws -> Void,
                open: @escaping @Sendable () async throws -> Void,
                restoreLifecycle: @escaping @Sendable (MiniAppRestoreLifecycle?) -> MiniAppRestoreLifecycle) {
        precondition(id.isValid)
        self.id = id
        self.prepare = prepare
        self.close = close
        self.open = open
        self.restoreLifecycle = restoreLifecycle
    }
}
