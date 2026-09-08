import Foundation
import XCTest
import JibunKitCore
import JibunKitBackup
import RecordsFeature
import RecordsBackupIntegration
import ZIPFoundation

final class MiniAppBackupArchiveTests: XCTestCase, @unchecked Sendable {
    private actor Value {
        var data = Data("live".utf8)
        func set(_ data: Data) { self.data = data }
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func payloadProvider(_ value: Value) -> MiniAppBackupProvider {
        MiniAppBackupProvider(id: MiniAppID("counter"), export: {
            MiniAppBackupEntry(id: MiniAppID("counter"), schemaVersion: 1, payload: Data("backup".utf8))
        }, prepare: { entry in
            guard entry.schemaVersion == 1 else { throw MiniAppBackupError.unsupportedSchema(entry.schemaVersion) }
            return MiniAppPreparedRestore { await value.set(entry.payload) }
        })
    }

    func testMixedArchiveRestoresSelectedFilesAndLegacyPayloadIndependently() async throws {
        let root = try root()
        let source = try RecordStore(directory: root.appendingPathComponent("source"))
        let target = try RecordStore(directory: root.appendingPathComponent("target"))
        let record = Record(title: "Files", body: "Body")
        try await source.save(record)
        let attachment = try await source.addAttachment(to: record.id, name: "example.txt", data: Data("attachment".utf8))
        try await target.save(Record(title: "Keep"))
        let value = Value()
        let payload = payloadProvider(value)
        let recordsID = MiniAppID("records")
        var file: MiniAppBackupFile? = try await MiniAppBackupArchive.export(selected: [payload.id, recordsID], providers: [payload], fileProviders: [RecordsBackup.provider(store: source, id: recordsID)])
        let exportedURL = try XCTUnwrap(file?.url)
        var imported: ImportedMiniAppBackup? = try MiniAppBackupArchive.load(from: exportedURL)
        file = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(imported?.entries.map(\.id), [payload.id, recordsID])
        let targetProvider = RecordsBackup.provider(store: target, id: recordsID)
        var plan: MiniAppRestorePlan? = try imported?.prepareRestore(selected: [recordsID], providers: [payload], fileProviders: [targetProvider])
        let before = try await target.records()
        XCTAssertEqual(before.map(\.title), ["Keep"])
        try await plan?.apply()
        let restored = try await target.records()
        let data = try await target.attachmentData(recordID: record.id, attachmentID: attachment.id)
        let untouched = await value.data
        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertEqual(data, Data("attachment".utf8))
        XCTAssertEqual(untouched, Data("live".utf8))
        plan = try imported?.prepareRestore(selected: [payload.id], providers: [payload], fileProviders: [])
        weak var retainedImport = imported
        imported = nil
        XCTAssertNotNil(retainedImport, "Prepared plans must own their imported files")
        try await plan?.apply()
        plan = nil
        XCTAssertNil(retainedImport, "Completed, released plans must not leak temporary files")
        let applied = await value.data
        XCTAssertEqual(applied, Data("backup".utf8))
    }

    func testExistingJSONRemainsReadableAndRestorable() async throws {
        let root = try root()
        let value = Value()
        let provider = payloadProvider(value)
        let entry = try await provider.exportEntry()
        let url = root.appendingPathComponent("old.json")
        try MiniAppBackup(entries: [entry]).encoded().write(to: url)
        let imported = try MiniAppBackupArchive.load(from: url)
        let plan = try imported.prepareRestore(selected: [provider.id], providers: [provider], fileProviders: [])
        try await plan.apply()
        let result = await value.data
        XCTAssertEqual(result, entry.payload)
    }

    func testTraversalAbsolutePathsSymlinksAndCollidingNamesAreRejected() throws {
        let root = try root()
        let source = root.appendingPathComponent("source")
        try Data("data".utf8).write(to: source)
        let paths = [["../escape"], ["/absolute"], ["a/../escape"], ["a\\escape"], ["a", "A"], ["a//b"]]
        for (index, names) in paths.enumerated() {
            let url = root.appendingPathComponent("bad-\(index).zip")
            do {
                let archive = try Archive(url: url, accessMode: .create)
                for name in names { try archive.addEntry(with: name, fileURL: source) }
            }
            XCTAssertThrowsError(try MiniAppBackupArchive.load(from: url), names.joined(separator: ","))
        }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let url = root.appendingPathComponent("link.zip")
        do {
            let archive = try Archive(url: url, accessMode: .create)
            try archive.addEntry(with: "link", fileURL: link)
        }
        XCTAssertThrowsError(try MiniAppBackupArchive.load(from: url))
    }

    func testChecksumMismatchIsRejected() throws {
        let root = try root()
        let source = root.appendingPathComponent("source")
        try Data("CHECKSUM-FIXTURE".utf8).write(to: source)
        let url = root.appendingPathComponent("corrupt.zip")
        do {
            let archive = try Archive(url: url, accessMode: .create)
            try archive.addEntry(with: "manifest.json", fileURL: source, compressionMethod: .none)
        }
        var bytes = try Data(contentsOf: url)
        let range = try XCTUnwrap(bytes.range(of: Data("CHECKSUM-FIXTURE".utf8)))
        bytes[range.lowerBound] ^= 1
        try bytes.write(to: url)
        XCTAssertThrowsError(try MiniAppBackupArchive.load(from: url)) { error in
            XCTAssertEqual(error as? MiniAppBackupError, .invalidEntry)
        }
    }
}
