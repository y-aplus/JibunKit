import Foundation

public enum MiniAppContinuingError: Error, Equatable, Sendable {
    case admissionClosed, invalidIdentity, invalidJournal, coordinationFailed
}

/// Serializes asynchronous native operations in the app process. Use one gate
/// per owner/service, including App Intents. Native operations must not recursively
/// enter this gate. Cross-process business writes still require SharedState.
public actor MiniAppContinuingOperationGate {
    private var accepting = true
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func perform<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard accepting else { throw MiniAppContinuingError.admissionClosed }
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard accepting else { throw MiniAppContinuingError.admissionClosed }
        return try await operation()
    }

    /// Closing is durable only when composed with the Feature's persisted
    /// admission. Returns after the admitted native operation has settled;
    /// operations queued before close are rejected rather than started later.
    public func close() async {
        accepting = false
        await acquire()
        release()
    }

    public func open() { accepting = true }

    /// Reconciliation/cleanup must remain possible while admission is closed.
    /// Do not expose this as an ordinary Feature action or extension entry point.
    /// Cancellation is handled by the operation so pending OS cleanup is retained.
    public func performMaintenance<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !occupied { occupied = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { occupied = false }
        else { waiters.removeFirst().resume() }
    }
}
