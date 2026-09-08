import Foundation

/// A snapshot directory and Feature schema; directory lifecycle belongs to the caller.
/// The files must remain immutable and available until preparation/application ends.
public struct MiniAppFileBackupEntry: Sendable {
    public let id: MiniAppID
    public let schemaVersion: Int
    public let directory: URL

    public init(id: MiniAppID, schemaVersion: Int, directory: URL) throws {
        guard id.isValid, schemaVersion > 0, directory.isFileURL else { throw MiniAppBackupError.invalidEntry }
        self.id = id
        self.schemaVersion = schemaVersion
        self.directory = directory
    }
}

/// Optional file-based snapshot contract, independent of a particular archive codec.
public struct MiniAppFileBackupProvider: Sendable {
    public let id: MiniAppID
    private let write: @Sendable (URL) async throws -> Int
    private let prepare: @Sendable (MiniAppFileBackupEntry) throws -> MiniAppPreparedRestore

    public init(
        id: MiniAppID,
        export: @escaping @Sendable (URL) async throws -> Int,
        prepare: @escaping @Sendable (MiniAppFileBackupEntry) throws -> MiniAppPreparedRestore
    ) {
        self.id = id
        self.write = export
        self.prepare = prepare
    }

    /// Caller supplies a new destination; provider writes its consistent snapshot
    /// and returns the schema version. Partial output on failure is not a backup.
    public func exportEntry(to directory: URL) async throws -> MiniAppFileBackupEntry {
        guard id.isValid, directory.isFileURL else { throw MiniAppBackupError.invalidEntry }
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        let schema = try await write(directory)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true
        else { throw MiniAppBackupError.invalidEntry }
        return try MiniAppFileBackupEntry(id: id, schemaVersion: schema, directory: directory)
    }

    public func prepareRestore(_ entry: MiniAppFileBackupEntry) throws -> MiniAppPreparedRestore {
        guard entry.id == id else { throw MiniAppBackupError.missingID(id.rawValue) }
        return try prepare(entry)
    }
}

public extension MiniAppRestorePlan {
    init(fileEntries: [MiniAppFileBackupEntry], selected: Set<MiniAppID>, providers: [MiniAppFileBackupProvider]) throws {
        var entries: [MiniAppID: MiniAppFileBackupEntry] = [:]
        for entry in fileEntries {
            guard entries.updateValue(entry, forKey: entry.id) == nil else { throw MiniAppBackupError.duplicateID(entry.id.rawValue) }
        }
        var available: [MiniAppID: MiniAppFileBackupProvider] = [:]
        for provider in providers {
            guard available.updateValue(provider, forKey: provider.id) == nil else { throw MiniAppBackupError.duplicateID(provider.id.rawValue) }
        }
        var prepared: [MiniAppID: MiniAppPreparedRestore] = [:]
        for id in selected.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let entry = entries[id], let provider = available[id] else { throw MiniAppBackupError.missingID(id.rawValue) }
            prepared[id] = try provider.prepareRestore(entry)
        }
        try self.init(prepared: prepared)
    }
}
