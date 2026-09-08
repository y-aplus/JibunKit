import Foundation

public struct RecordAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
}

public struct Record: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var attachments: [RecordAttachment]
    /// Nil for records created before timestamps were stored; never invent dates.
    public let createdAt: Date?

    public init(id: UUID = UUID(), title: String, body: String = "") {
        self.id = id
        self.title = title
        self.body = body
        self.attachments = []
        self.createdAt = .now
    }
}

public enum RecordStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidData
    case missingRecord
    case missingAttachment
}

/// Use one store actor per directory. The caller supplies the storage location.
/// Cross-process writes require additional coordination by the application.
public actor RecordStore {
    private struct Index: Codable {
        var version = 2
        var records: [Record] = []
    }

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("records.json") }
    private var assets: URL { directory.appendingPathComponent("attachments", isDirectory: true) }

    public init(directory: URL) throws {
        guard directory.isFileURL else { throw RecordStoreError.invalidData }
        self.directory = directory
    }

    public func records() throws -> [Record] { try load().records }

    public func save(_ record: Record) throws {
        var index = try load()
        if let position = index.records.firstIndex(where: { $0.id == record.id }) {
            // Attachment membership is changed only by the attachment operations.
            guard record.attachments == index.records[position].attachments else { throw RecordStoreError.invalidData }
            index.records[position] = record
        } else {
            guard record.attachments.isEmpty else { throw RecordStoreError.invalidData }
            index.records.append(record)
        }
        try persist(index)
    }

    public func delete(id: UUID) throws {
        var index = try load()
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { throw RecordStoreError.missingRecord }
        let removed = index.records.remove(at: position)
        try persist(index)
        // Unreferenced files may remain after a cleanup failure; never roll back
        // a committed index or remove files still referenced by live records.
        for attachment in removed.attachments { try? FileManager.default.removeItem(at: assetURL(attachment.id)) }
    }

    @discardableResult
    public func addAttachment(to id: UUID, name: String, data: Data) throws -> RecordAttachment {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecordStoreError.invalidData }
        var index = try load()
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { throw RecordStoreError.missingRecord }
        let attachment = RecordAttachment(id: UUID(), name: name)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let destination = assetURL(attachment.id)
        try data.write(to: destination, options: .atomic)
        index.records[position].attachments.append(attachment)
        do { try persist(index) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return attachment
    }

    public func attachmentData(recordID: UUID, attachmentID: UUID) throws -> Data {
        guard let record = try load().records.first(where: { $0.id == recordID }) else { throw RecordStoreError.missingRecord }
        guard record.attachments.contains(where: { $0.id == attachmentID }) else { throw RecordStoreError.missingAttachment }
        return try Data(contentsOf: assetURL(attachmentID))
    }

    /// The caller holds security-scoped access for the duration of this call.
    @discardableResult
    public func importAttachment(to id: UUID, from source: URL) throws -> RecordAttachment {
        guard source.isFileURL,
              try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { throw RecordStoreError.invalidData }
        var index = try load()
        guard let position = index.records.firstIndex(where: { $0.id == id }) else { throw RecordStoreError.missingRecord }
        let attachment = RecordAttachment(id: UUID(), name: source.lastPathComponent)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let destination = assetURL(attachment.id)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            index.records[position].attachments.append(attachment)
            try persist(index)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return attachment
    }

    /// Makes an independent temporary copy. Callers own its cleanup and must not
    /// use the live attachment as a writable document for external applications.
    public func copyAttachment(recordID: UUID, attachmentID: UUID, to directory: URL) throws -> URL {
        guard directory.isFileURL else { throw RecordStoreError.invalidData }
        guard let record = try load().records.first(where: { $0.id == recordID }) else { throw RecordStoreError.missingRecord }
        guard let attachment = record.attachments.first(where: { $0.id == attachmentID }) else { throw RecordStoreError.missingAttachment }
        let fileExtension = (attachment.name as NSString).pathExtension
        var destination = directory.appendingPathComponent(UUID().uuidString)
        if !fileExtension.isEmpty { destination.appendPathExtension(fileExtension) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: assetURL(attachmentID), to: destination)
        return destination
    }

    public func removeAttachment(recordID: UUID, attachmentID: UUID) throws {
        var index = try load()
        guard let position = index.records.firstIndex(where: { $0.id == recordID }) else { throw RecordStoreError.missingRecord }
        guard index.records[position].attachments.contains(where: { $0.id == attachmentID }) else { throw RecordStoreError.missingAttachment }
        index.records[position].attachments.removeAll { $0.id == attachmentID }
        try persist(index)
        try? FileManager.default.removeItem(at: assetURL(attachmentID))
    }

    private func assetURL(_ id: UUID) -> URL { assets.appendingPathComponent(id.uuidString) }

    /// Creates a new, independently owned directory containing only referenced
    /// attachments. Destination must not exist. One actor keeps the index and
    /// attachment set consistent while copying, without loading attachments as Data.
    public func exportSnapshot(to destination: URL) throws {
        guard destination.isFileURL else { throw RecordStoreError.invalidData }
        let index = try load()
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".records-export-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Self.copySnapshot(index, from: assets, to: staging)
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    /// Validates and stages all files before replacing the live directory.
    /// Call only after the application has obtained overwrite confirmation.
    public func restoreSnapshot(from snapshot: URL) throws {
        let index = try Self.readSnapshot(snapshot)
        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".records-restore-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Self.copySnapshot(index, from: snapshot.appendingPathComponent("attachments", isDirectory: true), to: staging)
        if FileManager.default.fileExists(atPath: directory.path) {
            _ = try FileManager.default.replaceItemAt(directory, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: directory)
        }
    }

    /// Checks the complete snapshot without touching any live store. The caller
    /// must keep this directory immutable until restore finishes.
    public static func validateSnapshot(at snapshot: URL) throws {
        _ = try readSnapshot(snapshot)
    }

    private static func readSnapshot(_ snapshot: URL) throws -> Index {
        guard snapshot.isFileURL else { throw RecordStoreError.invalidData }
        try requireDirectory(snapshot)
        let indexFile = snapshot.appendingPathComponent("records.json")
        try requireRegularFile(indexFile)
        let index = try decodeIndex(Data(contentsOf: indexFile))
        try validate(index)
        let assets = snapshot.appendingPathComponent("attachments", isDirectory: true)
        try requireDirectory(assets)
        for attachment in index.records.flatMap(\.attachments) {
            try requireRegularFile(assets.appendingPathComponent(attachment.id.uuidString))
        }
        return index
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw RecordStoreError.invalidData }
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RecordStoreError.invalidData }
    }

    private static func copySnapshot(_ index: Index, from sourceAssets: URL, to destination: URL) throws {
        let destinationAssets = destination.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
        for attachment in index.records.flatMap(\.attachments) {
            let source = sourceAssets.appendingPathComponent(attachment.id.uuidString)
            try requireRegularFile(source)
            try FileManager.default.copyItem(at: source, to: destinationAssets.appendingPathComponent(attachment.id.uuidString))
        }
        try JSONEncoder().encode(index).write(to: destination.appendingPathComponent("records.json"), options: .atomic)
    }

    private func load() throws -> Index {
        let data: Data
        do { data = try Data(contentsOf: indexURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Index() }
        let index = try Self.decodeIndex(data)
        try Self.validate(index)
        return index
    }

    private static func validate(_ index: Index) throws {
        guard index.version == 2 else { throw RecordStoreError.unsupportedSchema(index.version) }
        let attachments = index.records.flatMap(\.attachments)
        guard Set(index.records.map(\.id)).count == index.records.count,
              Set(attachments.map(\.id)).count == attachments.count,
              index.records.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              attachments.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw RecordStoreError.invalidData }
    }

    private static func decodeIndex(_ data: Data) throws -> Index {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).version
        guard version == 1 || version == 2 else { throw RecordStoreError.unsupportedSchema(version) }
        var index = try decoder.decode(Index.self, from: data)
        // Version 1 has no createdAt. Optional decoding preserves that unknown
        // value, IDs and attachment membership. Reading alone never rewrites disk.
        index.version = 2
        try validate(index)
        return index
    }

    private func persist(_ index: Index) throws {
        try Self.validate(index)
        let data = try JSONEncoder().encode(index)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }
}
