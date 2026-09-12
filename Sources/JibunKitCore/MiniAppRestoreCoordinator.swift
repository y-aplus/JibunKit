import Foundation

/// Coordinates restores, snapshots, and opted-in store access across scenes in
/// one process. Database transactions and extension processes remain store-owned.
public actor MiniAppRestoreCoordinator {
    public static let shared = MiniAppRestoreCoordinator()

    public struct Conflict: Error, Sendable {
        public let owners: Set<MiniAppID>
    }

    private var active: Set<MiniAppID> = []
    private var storeAccesses: [MiniAppID: Int] = [:]
    private nonisolated let admission = MiniAppStoreAdmission()

    public struct Unavailable: Error, Sendable { public let owners: Set<MiniAppID> }

    public init() {}

    /// Management applies persisted admission synchronously before host events.
    /// Existing operations still finish; the exclusive reservation detects them.
    nonisolated func setAccessAllowed(_ allowed: Bool, for owner: MiniAppID) {
        admission.setAllowed(allowed, for: owner)
    }

    /// Enroll ordinary reads/writes in the same boundary used by restore and
    /// snapshot providers. Other ordinary accesses may run concurrently, including
    /// for this owner; the database still owns its transaction/connection policy.
    /// A restore/snapshot conflicts until every admitted operation returns.
    /// Do not launch unawaited store work from the operation or synchronously
    /// wait for a restore inside it. Use the same coordinator for every entrance.
    public func withStoreAccess<Value: Sendable>(
        for owner: MiniAppID,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        guard owner.isValid else { throw MiniAppBackupError.invalidEntry }
        try Task.checkCancellation()
        let unavailable = admission.unavailable(in: [owner])
        guard unavailable.isEmpty else { throw Unavailable(owners: unavailable) }
        guard !active.contains(owner) else { throw Conflict(owners: [owner]) }
        storeAccesses[owner, default: 0] += 1
        defer {
            if let count = storeAccesses[owner], count > 1 { storeAccesses[owner] = count - 1 }
            else { storeAccesses.removeValue(forKey: owner) }
        }
        return try await operation()
    }

    /// Runs an exclusive store migration, reset, or other maintenance operation.
    /// The reservation spans lifecycle stop, the operation, and lifecycle resume.
    /// Snapshot and restore providers already hold this reservation and must call
    /// their lower-level store operations directly instead of nesting this API.
    public func withStoreMaintenance<Value: Sendable>(
        for owner: MiniAppID,
        lifecycle: MiniAppRestoreLifecycle? = nil,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        guard owner.isValid else { throw MiniAppBackupError.invalidEntry }
        return try await perform(ids: [owner]) {
            if let lifecycle { return try await lifecycle.perform(operation) }
            return try await operation()
        }
    }

    /// Management alone can reserve a disabled owner to finish its cleanup.
    func withOwnerDeactivation<Value: Sendable>(for owner: MiniAppID,
        operation: @Sendable () async throws -> Value) async throws -> Value {
        try await perform(ids: [owner], allowUnavailable: true, operation: operation)
    }

    func perform<Value: Sendable>(ids: [MiniAppID], allowUnavailable: Bool = false,
        operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let requested = Set(ids)
        if !allowUnavailable {
            let unavailable = admission.unavailable(in: requested)
            guard unavailable.isEmpty else { throw Unavailable(owners: unavailable) }
        }
        let conflicts = active.union(storeAccesses.keys).intersection(requested)
        guard conflicts.isEmpty else { throw Conflict(owners: conflicts) }
        active.formUnion(requested)
        defer { active.subtract(requested) }
        return try await operation()
    }
}

/// Only small in-memory membership operations hold the lock; no callback or
/// asynchronous work runs under it. Store bytes still use their existing locks.
private final class MiniAppStoreAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var blocked: Set<MiniAppID> = []

    func setAllowed(_ allowed: Bool, for owner: MiniAppID) {
        lock.lock()
        defer { lock.unlock() }
        if allowed { blocked.remove(owner) } else { blocked.insert(owner) }
    }

    func unavailable(in owners: Set<MiniAppID>) -> Set<MiniAppID> {
        lock.lock()
        defer { lock.unlock() }
        return blocked.intersection(owners)
    }
}
