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

    public func exportEntry() async throws -> MiniAppBackupEntry {
        let entry = try await export()
        guard entry.id == id.rawValue else { throw MiniAppBackupError.invalidEntry }
        return entry
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

    /// File-based adapters can reuse the same ordered execution and failure report.
    public init(prepared: [MiniAppID: MiniAppPreparedRestore]) throws {
        guard prepared.keys.allSatisfy(\.isValid) else { throw MiniAppBackupError.invalidEntry }
        ids = prepared.keys.sorted { $0.rawValue < $1.rawValue }
        operations = ids.compactMap { prepared[$0] }
    }

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

    public func apply(lifecycles: [MiniAppID: MiniAppRestoreLifecycle] = [:]) async throws {
        var completed: [MiniAppID] = []
        for (id, operation) in zip(ids, operations) {
            do {
                if let lifecycle = lifecycles[id] {
                    try await lifecycle.perform(operation.apply)
                } else {
                    try await operation.apply()
                }
                completed.append(id)
            } catch {
                throw MiniAppRestoreFailure(completed: completed, failed: id, reason: error.localizedDescription)
            }
        }
    }
}
