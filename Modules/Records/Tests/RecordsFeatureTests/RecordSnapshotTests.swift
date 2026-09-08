import Foundation
import XCTest
@testable import RecordsFeature

final class RecordSnapshotTests: XCTestCase, @unchecked Sendable {
    func testVersionOneReadAndRestorePreserveUnknownDateAndAttachment() async throws {
        let root = try root()
        let old = root.appendingPathComponent("old")
        let assets = old.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let id = UUID()
        let attachmentID = UUID()
        let original = Data("""
        {"version":1,"records":[{"id":"\(id.uuidString)","title":"Old","body":"Body","attachments":[{"id":"\(attachmentID.uuidString)","name":"old.txt"}]}]}
        """.utf8)
        let indexURL = old.appendingPathComponent("records.json")
        try original.write(to: indexURL)
        try Data("kept".utf8).write(to: assets.appendingPathComponent(attachmentID.uuidString))
        let store = try RecordStore(directory: old)
        var record = try await store.records()[0]
        XCTAssertNil(record.createdAt)
        XCTAssertEqual(try Data(contentsOf: indexURL), original)
        let target = try RecordStore(directory: root.appendingPathComponent("restored"))
        try RecordStore.validateSnapshot(at: old)
        try await target.restoreSnapshot(from: old)
        let restored = try await target.records()[0]
        let restoredData = try await target.attachmentData(recordID: id, attachmentID: attachmentID)
        XCTAssertEqual(restored.id, id)
        XCTAssertNil(restored.createdAt)
        XCTAssertEqual(restoredData, Data("kept".utf8))
        record.title = "Edited"
        try await store.save(record)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        let reopened = try RecordStore(directory: old)
        let migrated = try await reopened.records()[0]
        XCTAssertNil(migrated.createdAt)
        let newRecord = Record(title: "New")
        try await reopened.save(newRecord)
        let records = try await reopened.records()
        XCTAssertEqual(records.last?.createdAt, newRecord.createdAt)
    }

    func testFutureSchemaIsRejectedWithoutDecodingOrRewritingItsRecords() async throws {
        let root = try root()
        let url = root.appendingPathComponent("records.json")
        let future = Data(#"{"version":99,"records":"future representation"}"#.utf8)
        try future.write(to: url)
        let store = try RecordStore(directory: root)
        do {
            try await store.save(Record(title: "Must not overwrite"))
            XCTFail("Future schema accepted")
        } catch {
            XCTAssertEqual(error as? RecordStoreError, .unsupportedSchema(99))
        }
        XCTAssertEqual(try Data(contentsOf: url), future)
    }

    private func root() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: path) }
        return path
    }

    func testSnapshotRestoresRecordsAndAttachmentsAcrossStores() async throws {
        let root = try root()
        let source = try RecordStore(directory: root.appendingPathComponent("source"))
        let targetURL = root.appendingPathComponent("target")
        let target = try RecordStore(directory: targetURL)
        let record = Record(title: "Snapshot", body: "Text")
        try await source.save(record)
        let attachment = try await source.addAttachment(to: record.id, name: "file.txt", data: Data("original".utf8))
        let snapshot = root.appendingPathComponent("snapshot")
        try await source.exportSnapshot(to: snapshot)
        try await target.save(Record(title: "Replace me"))
        try await source.delete(id: record.id)
        try await target.restoreSnapshot(from: snapshot)
        let reopened = try RecordStore(directory: targetURL)
        let restored = try await reopened.records()
        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertEqual(restored[0].attachments.map(\.id), [attachment.id])
        let data = try await reopened.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(data, Data("original".utf8))
        let remainingSource = try await source.records()
        XCTAssertTrue(remainingSource.isEmpty)
    }

    func testMissingAttachmentRejectsRestoreWithoutChangingLiveData() async throws {
        let root = try root()
        let store = try RecordStore(directory: root.appendingPathComponent("live"))
        let record = Record(title: "Keep")
        try await store.save(record)
        let attachment = try await store.addAttachment(to: record.id, name: "file", data: Data([1, 2]))
        let snapshot = root.appendingPathComponent("snapshot")
        try await store.exportSnapshot(to: snapshot)
        try FileManager.default.removeItem(at: snapshot.appendingPathComponent("attachments").appendingPathComponent(attachment.id.uuidString))
        do { try await store.restoreSnapshot(from: snapshot); XCTFail("Incomplete snapshot accepted") }
        catch { }
        let records = try await store.records()
        XCTAssertEqual(records.map(\.title), ["Keep"])
        let data = try await store.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(data, Data([1, 2]))
    }
}
