import Foundation
import JibunKitCore
import RecordsFeature

/// The Feature owns its snapshot schema; this adapter owns the host contract.
public enum RecordsBackup {
    public static func provider(store: RecordStore, id: MiniAppID) -> MiniAppFileBackupProvider {
        MiniAppFileBackupProvider(id: id, export: { destination in
            try await store.exportSnapshot(to: destination)
            return 1
        }, prepare: { entry in
            guard entry.schemaVersion == 1 else { throw RecordStoreError.unsupportedSchema(entry.schemaVersion) }
            try RecordStore.validateSnapshot(at: entry.directory)
            return MiniAppPreparedRestore {
                // Recheck on apply as well: a missing/replaced snapshot must not
                // cause a partially copied live store after confirmation.
                try await store.restoreSnapshot(from: entry.directory)
            }
        })
    }
}
