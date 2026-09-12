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

    func testInjectedBoundaryCoversOrdinaryOperationsAndExclusiveMigrationReset() async throws {
        let root = try directory()
        let legacyID = UUID()
        let legacy = Data("""
        {"version":1,"records":[{"id":"\(legacyID.uuidString)","title":"Legacy","body":"","attachments":[]}]}
        """.utf8)
        try legacy.write(to: root.appendingPathComponent("records.json"))
        let boundary = RecordStoreBoundaryProbe()
        let store = try RecordStore(directory: root, operations: boundary)
        let migrated = try await store.migrateIfNeeded()
        XCTAssertTrue(migrated)
        let alreadyCurrent = try await store.migrateIfNeeded()
        XCTAssertFalse(alreadyCurrent)
        var record = try await store.records()[0]
        record.title = "Updated"
        try await store.save(record)
        let attachment = try await store.addAttachment(to: record.id, name: "a.txt", data: Data([1]))
        _ = try await store.attachmentData(recordID: record.id, attachmentID: attachment.id)
        _ = try await store.copyAttachment(recordID: record.id, attachmentID: attachment.id, to: directory())
        try await store.removeAttachment(recordID: record.id, attachmentID: attachment.id)
        let external = try directory().appendingPathComponent("import.txt")
        try Data([2]).write(to: external)
        _ = try await store.importAttachment(to: record.id, from: external)
        try await store.delete(id: record.id)
        let resetRecord = Record(title: "Reset")
        try await store.save(resetRecord)
        let resetAttachment = try await store.addAttachment(to: resetRecord.id, name: "reset.txt", data: Data([3]))
        try await store.reset()
        let recordsAfterReset = try await store.records()
        XCTAssertTrue(recordsAfterReset.isEmpty)
        let counts = await boundary.counts
        XCTAssertEqual(counts.access, 11)
        XCTAssertEqual(counts.maintenance, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("attachments").appendingPathComponent(resetAttachment.id.uuidString).path))
    }

    func testUnknownAndCorruptMigrationPreserveOriginalBytes() async throws {
        for bytes in [
            Data("{\"version\":99,\"records\":[]}".utf8),
            Data("{\"version\":2,\"records\":[{\"broken\":true}]}".utf8)
        ] {
            let root = try directory()
            let index = root.appendingPathComponent("records.json")
            try bytes.write(to: index)
            let store = try RecordStore(directory: root)
            do { _ = try await store.migrateIfNeeded(); XCTFail("Invalid index accepted") } catch {}
            XCTAssertEqual(try Data(contentsOf: index), bytes)
        }
    }
}

private actor RecordStoreBoundaryProbe: RecordStoreOperationBoundary {
    private var accessCount = 0
    private var maintenanceCount = 0
    var counts: (access: Int, maintenance: Int) { (accessCount, maintenanceCount) }

    func withAccess<Value: Sendable>(operation: @Sendable () async throws -> Value) async throws -> Value {
        accessCount += 1
        return try await operation()
    }

    func withMaintenance<Value: Sendable>(operation: @Sendable () async throws -> Value) async throws -> Value {
        maintenanceCount += 1
        return try await operation()
    }
}
