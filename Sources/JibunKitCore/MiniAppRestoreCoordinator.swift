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

    public init() {}

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
        guard !active.contains(owner) else { throw Conflict(owners: [owner]) }
        storeAccesses[owner, default: 0] += 1
        defer {
            if let count = storeAccesses[owner], count > 1 { storeAccesses[owner] = count - 1 }
            else { storeAccesses.removeValue(forKey: owner) }
        }
        return try await operation()
    }

    func perform<Value: Sendable>(ids: [MiniAppID], operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let requested = Set(ids)
        let conflicts = active.union(storeAccesses.keys).intersection(requested)
        guard conflicts.isEmpty else { throw Conflict(owners: conflicts) }
        active.formUnion(requested)
        defer { active.subtract(requested) }
        return try await operation()
    }
}
