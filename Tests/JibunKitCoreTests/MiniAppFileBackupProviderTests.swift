import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppFileBackupProviderTests: XCTestCase, @unchecked Sendable {
    private actor Recorder {
        var ids: [MiniAppID] = []
        func append(_ id: MiniAppID) { ids.append(id) }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testSnapshotExportPreservesFilesAndRejectsExistingDestination() async throws {
        let root = try temporaryDirectory()
        let destination = root.appendingPathComponent("snapshot")
        let provider = MiniAppFileBackupProvider(id: MiniAppID("records"), export: { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("attachment".utf8).write(to: url.appendingPathComponent("asset"))
            return 2
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let entry = try await provider.exportEntry(to: destination)
        XCTAssertEqual(entry.schemaVersion, 2)
        XCTAssertEqual(entry.id, MiniAppID("records"))
        do {
            _ = try await provider.exportEntry(to: destination)
            XCTFail("Existing snapshots must not be overwritten")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteFileExists.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: entry.directory.appendingPathComponent("asset")), Data("attachment".utf8))
    }

    func testRegularFileCannotBeExportedAsSnapshotDirectory() async throws {
        let destination = try temporaryDirectory().appendingPathComponent("snapshot")
        let provider = MiniAppFileBackupProvider(id: MiniAppID("records"), export: { url in
            try Data().write(to: url)
            return 1
        }, prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await provider.exportEntry(to: destination)
            XCTFail("Expected directory validation")
        } catch {
            XCTAssertEqual(error as? MiniAppBackupError, .invalidEntry)
        }
    }

    func testAllSelectedFeaturesValidateBeforeAnyLiveMutation() async throws {
        let root = try temporaryDirectory()
        let recorder = Recorder()
        let entries = try ["a", "b"].map {
            try MiniAppFileBackupEntry(id: MiniAppID($0), schemaVersion: 1, directory: root)
        }
        let providers = entries.map { entry in
            MiniAppFileBackupProvider(id: entry.id, export: { _ in 1 }, prepare: { candidate in
                if candidate.id == MiniAppID("b") { throw MiniAppBackupError.invalidEntry }
                return MiniAppPreparedRestore { await recorder.append(candidate.id) }
            })
        }
        XCTAssertThrowsError(try MiniAppRestorePlan(fileEntries: entries,
            selected: Set(entries.map(\.id)), providers: providers))
        let applied = await recorder.ids
        XCTAssertEqual(applied, [])
        // An invalid, unselected Feature must not prevent restoring a valid one.
        let selected = try MiniAppRestorePlan(fileEntries: entries, selected: [MiniAppID("a")], providers: providers)
        try await selected.apply()
        let afterSelection = await recorder.ids
        XCTAssertEqual(afterSelection, [MiniAppID("a")])
    }

    func testApplyFailureReportsCompletedAndLeavesLaterFeaturesUntouched() async throws {
        let root = try temporaryDirectory()
        let recorder = Recorder()
        let entries = try ["c", "b", "a"].map {
            try MiniAppFileBackupEntry(id: MiniAppID($0), schemaVersion: 1, directory: root)
        }
        let providers = entries.map { entry in
            MiniAppFileBackupProvider(id: entry.id, export: { _ in 1 }, prepare: { candidate in
                MiniAppPreparedRestore {
                    if candidate.id == MiniAppID("b") { throw MiniAppBackupError.invalidEntry }
                    await recorder.append(candidate.id)
                }
            })
        }
        let plan = try MiniAppRestorePlan(fileEntries: entries, selected: Set(entries.map(\.id)), providers: providers)
        do {
            try await plan.apply()
            XCTFail("Expected apply failure")
        } catch let failure as MiniAppRestoreFailure {
            XCTAssertEqual(failure.completed, [MiniAppID("a")])
            XCTAssertEqual(failure.failed, MiniAppID("b"))
        }
        let applied = await recorder.ids
        XCTAssertEqual(applied, [MiniAppID("a")])
        XCTAssertThrowsError(try MiniAppRestorePlan(fileEntries: entries + [entries[0]], selected: [], providers: providers))
        XCTAssertThrowsError(try MiniAppRestorePlan(fileEntries: entries, selected: [], providers: providers + [providers[0]]))
        XCTAssertThrowsError(try MiniAppRestorePlan(fileEntries: entries, selected: [MiniAppID("missing")], providers: providers))
    }
}
