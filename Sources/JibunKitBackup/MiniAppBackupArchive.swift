import Foundation
import JibunKitCore
import ZIPFoundation

/// Transport metadata, separate from each Feature's schema and snapshot layout.
fileprivate struct Manifest: Codable {
    let format: String
    let version: Int
    let createdAt: Date
    let entries: [Item]

    struct Item: Codable {
        let id: String
        let schemaVersion: Int
        let storage: ImportedMiniAppBackup.Storage
        let location: String
    }
}

/// Validated import with privately owned files. Retain through confirmation;
/// prepared plans also retain it until their operations are released.
public final class ImportedMiniAppBackup: Sendable {
    public enum Storage: String, Codable, Sendable { case payload, files }
    public struct Entry: Sendable {
        public let id: MiniAppID
        public let schemaVersion: Int
        public let storage: Storage
        fileprivate let payload: Data?
        fileprivate let directory: URL?
    }
    public let createdAt: Date
    public let entries: [Entry]
    private let workspace: BackupWorkspace?

    public init(legacy: MiniAppBackup) {
        createdAt = legacy.createdAt
        entries = legacy.entries.map {
            Entry(id: MiniAppID($0.id), schemaVersion: $0.schemaVersion, storage: .payload, payload: $0.payload, directory: nil)
        }
        workspace = nil
    }

    fileprivate init(manifest: Manifest, root: URL, workspace: BackupWorkspace) throws {
        guard manifest.format == "JibunKitFileBackup", manifest.version == 1 else { throw MiniAppBackupError.unsupportedFormat }
        guard manifest.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw MiniAppBackupError.invalidEntry }
        var ids = Set<String>()
        var locations = Set<String>()
        entries = try manifest.entries.map { item in
            guard MiniAppID(item.id).isValid, item.schemaVersion > 0,
                  let index = Int(item.location), index >= 0, String(index) == item.location,
                  locations.insert(item.location).inserted else { throw MiniAppBackupError.invalidEntry }
            guard ids.insert(item.id).inserted else { throw MiniAppBackupError.duplicateID(item.id) }
            let directory = root.appendingPathComponent("features").appendingPathComponent(item.location)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw MiniAppBackupError.invalidEntry }
            let payload = item.storage == .payload ? try Data(contentsOf: directory.appendingPathComponent("payload")) : nil
            return Entry(id: MiniAppID(item.id), schemaVersion: item.schemaVersion, storage: item.storage,
                         payload: payload, directory: item.storage == .files ? directory : nil)
        }
        createdAt = manifest.createdAt
        self.workspace = workspace
    }

    public func prepareRestore(selected: Set<MiniAppID>, providers: [MiniAppBackupProvider], fileProviders: [MiniAppFileBackupProvider]) throws -> MiniAppRestorePlan {
        var payloads: [MiniAppID: MiniAppBackupProvider] = [:]
        var files: [MiniAppID: MiniAppFileBackupProvider] = [:]
        for provider in providers {
            guard payloads.updateValue(provider, forKey: provider.id) == nil else { throw MiniAppBackupError.duplicateID(provider.id.rawValue) }
        }
        for provider in fileProviders {
            guard files.updateValue(provider, forKey: provider.id) == nil else { throw MiniAppBackupError.duplicateID(provider.id.rawValue) }
        }
        var operations: [MiniAppID: MiniAppPreparedRestore] = [:]
        for id in selected.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let entry = entries.first(where: { $0.id == id }) else { throw MiniAppBackupError.missingID(id.rawValue) }
            let prepared: MiniAppPreparedRestore
            switch entry.storage {
            case .payload:
                guard let provider = payloads[id], let payload = entry.payload else { throw MiniAppBackupError.missingID(id.rawValue) }
                prepared = try provider.prepareRestore(MiniAppBackupEntry(id: id, schemaVersion: entry.schemaVersion, payload: payload))
            case .files:
                guard let provider = files[id], let directory = entry.directory else { throw MiniAppBackupError.missingID(id.rawValue) }
                prepared = try provider.prepareRestore(MiniAppFileBackupEntry(id: id, schemaVersion: entry.schemaVersion, directory: directory))
            }
            operations[id] = MiniAppPreparedRestore { [self] in
                defer { withExtendedLifetime(self) {} }
                try await prepared.apply()
            }
        }
        return try MiniAppRestorePlan(prepared: operations)
    }
}

public enum MiniAppBackupArchive {
    /// Snapshots are gathered sequentially, then streamed into a standard ZIP.
    /// When both contracts exist for an ID, new exports prefer the file provider.
    public static func export(selected: Set<MiniAppID>, providers: [MiniAppBackupProvider], fileProviders: [MiniAppFileBackupProvider],
                              coordinator: MiniAppRestoreCoordinator = .shared) async throws -> MiniAppBackupFile {
        let workspace = try BackupWorkspace()
        let root = workspace.directory.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("features"), withIntermediateDirectories: true)
        var payloads: [MiniAppID: MiniAppBackupProvider] = [:]
        var files: [MiniAppID: MiniAppFileBackupProvider] = [:]
        for provider in providers {
            guard payloads.updateValue(provider, forKey: provider.id) == nil else { throw MiniAppBackupError.duplicateID(provider.id.rawValue) }
        }
        for provider in fileProviders {
            guard files.updateValue(provider, forKey: provider.id) == nil else { throw MiniAppBackupError.duplicateID(provider.id.rawValue) }
        }
        var items: [Manifest.Item] = []
        for (index, id) in selected.sorted(by: { $0.rawValue < $1.rawValue }).enumerated() {
            try Task.checkCancellation()
            let location = String(index)
            let destination = root.appendingPathComponent("features").appendingPathComponent(location)
            if let provider = files[id] {
                let entry = try await provider.exportEntry(to: destination, coordinator: coordinator)
                items.append(Manifest.Item(id: id.rawValue, schemaVersion: entry.schemaVersion, storage: .files, location: location))
            } else if let provider = payloads[id] {
                let entry = try await provider.exportEntry(coordinator: coordinator)
                // Validate the existing payload contract before writing metadata.
                _ = try MiniAppBackup(entries: [entry])
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                try entry.payload.write(to: destination.appendingPathComponent("payload"), options: .atomic)
                items.append(Manifest.Item(id: id.rawValue, schemaVersion: entry.schemaVersion, storage: .payload, location: location))
            } else { throw MiniAppBackupError.missingID(id.rawValue) }
        }
        let manifest = Manifest(format: "JibunKitFileBackup", version: 1, createdAt: .now, entries: items)
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        let url = workspace.directory.appendingPathComponent("backup.zip")
        try writeZIP(from: root, to: url)
        return MiniAppBackupFile(url: url, workspace: workspace)
    }

    /// Caller holds security-scoped access during this call. The result owns its
    /// imported copies and does not depend on access to the original document.
    public static func load(from url: URL) throws -> ImportedMiniAppBackup {
        let handle = try FileHandle(forReadingFrom: url)
        let signature: Data
        do { signature = try handle.read(upToCount: 4) ?? Data(); try handle.close() }
        catch { try? handle.close(); throw error }
        if signature != Data([0x50, 0x4b, 0x03, 0x04]) {
            return ImportedMiniAppBackup(legacy: try MiniAppBackup.decode(Data(contentsOf: url)))
        }
        let workspace = try BackupWorkspace()
        let root = workspace.directory.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archive = try Archive(url: url, accessMode: .read)
        var seen = Set<String>()
        // Reject every unsafe path before any entry is extracted.
        for entry in archive {
            guard entry.type != .symlink else { throw MiniAppBackupError.invalidEntry }
            let path = try safePath(entry.path, directory: entry.type == .directory)
            guard seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw MiniAppBackupError.invalidEntry }
        }
        for entry in archive {
            try Task.checkCancellation()
            let path = try safePath(entry.path, directory: entry.type == .directory)
            let checksum = try archive.extract(entry, to: root.appendingPathComponent(path), bufferSize: 64 * 1024)
            guard checksum == entry.checksum else { throw MiniAppBackupError.invalidEntry }
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        return try ImportedMiniAppBackup(manifest: manifest, root: root, workspace: workspace)
    }

    private static func safePath(_ raw: String, directory: Bool) throws -> String {
        let path = directory && raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw MiniAppBackupError.invalidEntry }
        return path
    }

    private static func writeZIP(from root: URL, to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        var seen = Set<String>()
        var directories = [""]
        // Construct archive names from directory entries, never by subtracting
        // absolute URL prefixes (/var and /private/var can name the same place).
        while let relativeDirectory = directories.popLast() {
            let directory = relativeDirectory.isEmpty ? root : root.appendingPathComponent(relativeDirectory)
            let children = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            for file in children {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { throw MiniAppBackupError.invalidEntry }
                let path = relativeDirectory.isEmpty ? file.lastPathComponent : relativeDirectory + "/" + file.lastPathComponent
                _ = try safePath(path, directory: values.isDirectory == true)
                guard seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw MiniAppBackupError.invalidEntry }
                try archive.addEntry(with: path, fileURL: file, compressionMethod: .none, bufferSize: 64 * 1024)
                if values.isDirectory == true { directories.append(path) }
            }
        }
    }
}
