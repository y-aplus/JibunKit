import Foundation
import XCTest
@testable import RecordsFeature

final class RecordStoreTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testEditAttachmentsReopenAndIndependentStorage() async throws {
        let root = try directory()
        let store = try RecordStore(directory: root)
        let other = try RecordStore(directory: directory())
        let first = Record(title: "First", body: "Body")
        try await store.save(first)
        try await other.save(Record(title: "Other"))
        let attachment = try await store.addAttachment(to: first.id, name: "../旅行.txt", data: Data("attachment".utf8))
        let reopened = try RecordStore(directory: root)
        var record = try await reopened.records()[0]
        record.title = "Edited"
        try await reopened.save(record)
        let data = try await reopened.attachmentData(recordID: first.id, attachmentID: attachment.id)
        XCTAssertEqual(data, Data("attachment".utf8))
        let others = try await other.records()
        XCTAssertEqual(others.map(\.title), ["Other"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("旅行.txt").path))
        try await reopened.removeAttachment(recordID: first.id, attachmentID: attachment.id)
        let afterRemoval = try await reopened.records()
        XCTAssertTrue(afterRemoval[0].attachments.isEmpty)
        try await reopened.delete(id: first.id)
        let afterDelete = try await reopened.records()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testRejectedEditPreservesIndexAndAttachment() async throws {
        let root = try directory()
        let store = try RecordStore(directory: root)
        let record = Record(title: "Keep")
        try await store.save(record)
        let attachment = try await store.addAttachment(to: record.id, name: "file", data: Data([1, 2, 3]))
        let before = try Data(contentsOf: root.appendingPathComponent("records.json"))
        var invalid = try await store.records()[0]
        invalid.title = " "
        do { try await store.save(invalid); XCTFail("Invalid edit accepted") }
        catch { XCTAssertEqual(error as? RecordStoreError, .invalidData) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("records.json")), before)
        let data = try await store.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testCorruptIndexIsNeverReplacedWithEmptyStore() async throws {
        let root = try directory()
        let url = root.appendingPathComponent("records.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        let store = try RecordStore(directory: root)
        do { try await store.save(Record(title: "New")); XCTFail("Corruption ignored") }
        catch { }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testAttachmentWriteFailureLeavesRecordUnchanged() async throws {
        let root = try directory()
        let store = try RecordStore(directory: root)
        let record = Record(title: "Keep")
        try await store.save(record)
        let before = try Data(contentsOf: root.appendingPathComponent("records.json"))
        // A file occupies the required asset directory, producing a real I/O failure.
        try Data([9]).write(to: root.appendingPathComponent("attachments"))
        do {
            try await store.addAttachment(to: record.id, name: "file", data: Data([1]))
            XCTFail("Attachment write unexpectedly succeeded")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("records.json")), before)
        let records = try await store.records()
        XCTAssertEqual(records, [record])
    }

    func testFileImportAndPreviewCopyPreserveOwnedAttachment() async throws {
        let root = try directory()
        let external = try directory().appendingPathComponent("report.txt")
        try Data("source".utf8).write(to: external)
        let store = try RecordStore(directory: root)
        let record = Record(title: "Files")
        try await store.save(record)
        let attachment = try await store.importAttachment(to: record.id, from: external)
        XCTAssertEqual(attachment.name, "report.txt")
        try Data("changed externally".utf8).write(to: external)
        let preview = try await store.copyAttachment(recordID: record.id, attachmentID: attachment.id, to: directory())
        XCTAssertEqual(preview.pathExtension, "txt")
        XCTAssertEqual(try Data(contentsOf: preview), Data("source".utf8))
        try Data("changed preview".utf8).write(to: preview)
        let stored = try await store.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(stored, Data("source".utf8))
        do {
            try await store.importAttachment(to: record.id, from: root)
            XCTFail("Directory accepted as attachment")
        } catch { }
        let records = try await store.records()
        XCTAssertEqual(records[0].attachments, [attachment])
    }
}
