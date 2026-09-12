import Foundation
import JibunKitCore
import RecordsFeature

/// Connects Records' Core-independent operation boundary to the host's shared
/// owner reservation. The same instance/owner must also be used by backup.
public struct RecordsStoreOperationBoundary: RecordStoreOperationBoundary {
    public let owner: MiniAppID
    public let coordinator: MiniAppRestoreCoordinator
    public let lifecycle: MiniAppRestoreLifecycle?

    public init(
        owner: MiniAppID,
        coordinator: MiniAppRestoreCoordinator = .shared,
        lifecycle: MiniAppRestoreLifecycle? = nil
    ) {
        self.owner = owner
        self.coordinator = coordinator
        self.lifecycle = lifecycle
    }

    public func withAccess<Value: Sendable>(
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await coordinator.withStoreAccess(for: owner, operation: operation)
    }

    public func withMaintenance<Value: Sendable>(
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await coordinator.withStoreMaintenance(for: owner, lifecycle: lifecycle, operation: operation)
    }
}

/// The Feature owns its snapshot schema; this adapter owns the host contract.
public enum RecordsBackup {
    public static func provider(
        store: RecordStore,
        id: MiniAppID,
        clearReminders: @escaping @Sendable () async -> Void = {}
    ) -> MiniAppFileBackupProvider {
        MiniAppFileBackupProvider(id: id, export: { destination in
            try await store.exportSnapshot(to: destination)
            return 2
        }, prepare: { entry in
            guard entry.schemaVersion == 1 || entry.schemaVersion == 2 else { throw RecordStoreError.unsupportedSchema(entry.schemaVersion) }
            try RecordStore.validateSnapshot(at: entry.directory)
            return MiniAppPreparedRestore {
                // Recheck on apply as well: a missing/replaced snapshot must not
                // cause a partially copied live store after confirmation.
                try await store.restoreSnapshot(from: entry.directory)
                // A snapshot does not contain OS reservations. Clear the old
                // store's reminders only after its replacement succeeds.
                await clearReminders()
            }
        })
    }
}
