import Foundation
import XCTest
import JibunKitCore
import RecordsFeature
import RecordsBackupIntegration

final class RecordsBackupIntegrationTests: XCTestCase, @unchecked Sendable {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testPreparePreservesLiveDataThenApplyRestoresAttachmentAndIDs() async throws {
        let root = try root()
        let source = try RecordStore(directory: root.appendingPathComponent("source"))
        let liveURL = root.appendingPathComponent("live")
        let live = try RecordStore(directory: liveURL)
        let other = try RecordStore(directory: root.appendingPathComponent("other"))
        let record = Record(title: "Exported", body: "Body")
        try await source.save(record)
        let attachment = try await source.addAttachment(to: record.id, name: "file.txt", data: Data("attachment".utf8))
        try await live.save(Record(title: "Keep until confirmed"))
        try await other.save(Record(title: "Unselected"))
        let id = MiniAppID("records")
        let entry = try await RecordsBackup.provider(store: source, id: id).exportEntry(to: root.appendingPathComponent("snapshot"))
        let reminders = ReminderCleanupProbe()
        let provider = RecordsBackup.provider(store: live, id: id, clearReminders: {
            let titles = (try? await live.records().map(\.title)) ?? ["read failed"]
            await reminders.record(titles)
        })
        let plan = try MiniAppRestorePlan(fileEntries: [entry], selected: [id], providers: [provider])
        let before = try await live.records()
        XCTAssertEqual(before.map(\.title), ["Keep until confirmed"])
        let beforeCleanup = await reminders.observedTitles
        XCTAssertTrue(beforeCleanup.isEmpty, "Preparation must preserve existing reminders")
        try await plan.apply()
        let afterCleanup = await reminders.observedTitles
        XCTAssertEqual(afterCleanup, [["Exported"]], "Clear reservations once, after the new data is committed")
        let reopened = try RecordStore(directory: liveURL)
        let restored = try await reopened.records()
        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertEqual(restored[0].attachments.map(\.id), [attachment.id])
        let data = try await reopened.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(data, Data("attachment".utf8))
        let untouched = try await other.records()
        XCTAssertEqual(untouched.map(\.title), ["Unselected"])
    }

    func testInvalidSchemaAndMissingAttachmentAreRejectedDuringPreparation() async throws {
        let root = try root()
        let store = try RecordStore(directory: root.appendingPathComponent("live"))
        let record = Record(title: "Keep")
        try await store.save(record)
        let attachment = try await store.addAttachment(to: record.id, name: "file", data: Data([1, 2]))
        let id = MiniAppID("records")
        let reminders = ReminderCleanupProbe()
        let provider = RecordsBackup.provider(store: store, id: id, clearReminders: {
            await reminders.record([])
        })
        let entry = try await provider.exportEntry(to: root.appendingPathComponent("snapshot"))
        let future = try MiniAppFileBackupEntry(id: id, schemaVersion: 99, directory: entry.directory)
        XCTAssertThrowsError(try provider.prepareRestore(future))
        let prepared = try provider.prepareRestore(entry)
        try FileManager.default.removeItem(at: entry.directory.appendingPathComponent("attachments").appendingPathComponent(attachment.id.uuidString))
        XCTAssertThrowsError(try provider.prepareRestore(entry))
        do {
            try await prepared.apply()
            XCTFail("Snapshot removed after confirmation must fail without replacing live data")
        } catch { }
        let records = try await store.records()
        let data = try await store.attachmentData(recordID: record.id, attachmentID: attachment.id)
        XCTAssertEqual(records.map(\.id), [record.id])
        XCTAssertEqual(data, Data([1, 2]))
        let cleanup = await reminders.observedTitles
        XCTAssertTrue(cleanup.isEmpty, "Rejected preparation and failed application must preserve reservations")
    }

    func testSymlinkAttachmentDirectoryIsRejectedBeforeRestoration() async throws {
        let root = try root()
        let store = try RecordStore(directory: root.appendingPathComponent("live"))
        let record = Record(title: "Keep")
        try await store.save(record)
        _ = try await store.addAttachment(to: record.id, name: "file", data: Data([7]))
        let provider = RecordsBackup.provider(store: store, id: MiniAppID("records"))
        let entry = try await provider.exportEntry(to: root.appendingPathComponent("snapshot"))
        let assets = entry.directory.appendingPathComponent("attachments")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: assets, to: outside)
        try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: outside)
        XCTAssertThrowsError(try provider.prepareRestore(entry))
        let records = try await store.records()
        XCTAssertEqual(records.map(\.id), [record.id])
    }
}

private actor ReminderCleanupProbe {
    private(set) var observedTitles: [[String]] = []
    func record(_ titles: [String]) { observedTitles.append(titles) }
}
