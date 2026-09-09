import Foundation
import JibunKitCore
import RecordsFeature

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
