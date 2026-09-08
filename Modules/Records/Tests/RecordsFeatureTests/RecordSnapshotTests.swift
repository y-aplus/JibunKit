import Foundation
import XCTest
@testable import RecordsFeature

final class RecordSnapshotTests: XCTestCase, @unchecked Sendable {
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
