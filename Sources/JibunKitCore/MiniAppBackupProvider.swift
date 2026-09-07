import Foundation

/// Validation must not mutate live state. The returned operation owns already
/// decoded/migrated state and applies it only after explicit user confirmation.
public struct MiniAppPreparedRestore: Sendable {
    public let apply: @Sendable () async throws -> Void

    public init(apply: @escaping @Sendable () async throws -> Void) {
        self.apply = apply
    }
}

public struct MiniAppBackupProvider: Sendable {
    public let id: MiniAppID
    public let export: @Sendable () async throws -> MiniAppBackupEntry
    private let prepare: @Sendable (MiniAppBackupEntry) throws -> MiniAppPreparedRestore

    public init(
        id: MiniAppID,
        export: @escaping @Sendable () async throws -> MiniAppBackupEntry,
        prepare: @escaping @Sendable (MiniAppBackupEntry) throws -> MiniAppPreparedRestore
    ) {
        self.id = id
        self.export = export
        self.prepare = prepare
    }

    public func prepareRestore(_ entry: MiniAppBackupEntry) throws -> MiniAppPreparedRestore {
        guard entry.id == id.rawValue else { throw MiniAppBackupError.missingID(id.rawValue) }
        return try prepare(entry)
    }
}

public struct MiniAppRestoreFailure: Error, Sendable {
    public let completed: [MiniAppID]
    public let failed: MiniAppID
    public let reason: String
}

/// Does not promise a transaction across independent Feature stores.
public struct MiniAppRestorePlan: Sendable {
    public let ids: [MiniAppID]
    private let operations: [MiniAppPreparedRestore]

    public init(backup: MiniAppBackup, selected: Set<MiniAppID>, providers: [MiniAppBackupProvider]) throws {
        var indexed: [MiniAppID: MiniAppBackupProvider] = [:]
        for provider in providers {
            guard indexed.updateValue(provider, forKey: provider.id) == nil else {
                throw MiniAppBackupError.duplicateID(provider.id.rawValue)
            }
        }
        let entries = try backup.selecting(selected)
        operations = try entries.map { entry in
            let id = MiniAppID(entry.id)
            guard let provider = indexed[id] else { throw MiniAppBackupError.missingID(entry.id) }
            return try provider.prepareRestore(entry)
        }
        ids = entries.map { MiniAppID($0.id) }
    }

    public func apply() async throws {
        var completed: [MiniAppID] = []
        for (id, operation) in zip(ids, operations) {
            do {
                try await operation.apply()
                completed.append(id)
            } catch {
                throw MiniAppRestoreFailure(completed: completed, failed: id, reason: error.localizedDescription)
            }
        }
    }
}
