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

    public init(id: UUID = UUID(), title: String, body: String = "") {
        self.id = id
        self.title = title
        self.body = body
        self.attachments = []
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
        var version = 1
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

    public func removeAttachment(recordID: UUID, attachmentID: UUID) throws {
        var index = try load()
        guard let position = index.records.firstIndex(where: { $0.id == recordID }) else { throw RecordStoreError.missingRecord }
        guard index.records[position].attachments.contains(where: { $0.id == attachmentID }) else { throw RecordStoreError.missingAttachment }
        index.records[position].attachments.removeAll { $0.id == attachmentID }
        try persist(index)
        try? FileManager.default.removeItem(at: assetURL(attachmentID))
    }

    private func assetURL(_ id: UUID) -> URL { assets.appendingPathComponent(id.uuidString) }

    private func load() throws -> Index {
        let data: Data
        do { data = try Data(contentsOf: indexURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Index() }
        let index = try JSONDecoder().decode(Index.self, from: data)
        try validate(index)
        return index
    }

    private func validate(_ index: Index) throws {
        guard index.version == 1 else { throw RecordStoreError.unsupportedSchema(index.version) }
        let attachments = index.records.flatMap(\.attachments)
        guard Set(index.records.map(\.id)).count == index.records.count,
              Set(attachments.map(\.id)).count == attachments.count,
              index.records.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              attachments.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw RecordStoreError.invalidData }
    }

    private func persist(_ index: Index) throws {
        try validate(index)
        let data = try JSONEncoder().encode(index)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }
}
