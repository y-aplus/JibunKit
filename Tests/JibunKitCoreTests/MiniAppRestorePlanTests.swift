import XCTest
@testable import JibunKitCore

final class MiniAppRestorePlanTests: XCTestCase {
    func testExportRejectsAnEntryForAnotherFeature() async throws {
        let provider = MiniAppBackupProvider(id: MiniAppID("a"), export: {
            MiniAppBackupEntry(id: MiniAppID("b"), schemaVersion: 1, payload: Data())
        }, prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await provider.exportEntry()
            XCTFail("Wrong Feature must not be exported")
        } catch {
            XCTAssertEqual(error as? MiniAppBackupError, .invalidEntry)
        }
    }
    private actor Recorder {
        var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }

    func testApplyFailureReportsCompletedFeatureAndStops() async throws {
        let recorder = Recorder()
        let entries = ["a", "b", "c"].map {
            MiniAppBackupEntry(id: MiniAppID($0), schemaVersion: 1, payload: Data())
        }
        let providers = entries.map { entry in
            MiniAppBackupProvider(id: MiniAppID(entry.id), export: { entry }, prepare: { _ in
                MiniAppPreparedRestore {
                    if entry.id == "b" { throw MiniAppBackupError.invalidEntry }
                    await recorder.append(entry.id)
                }
            })
        }
        let plan = try MiniAppRestorePlan(backup: MiniAppBackup(entries: entries),
                                         selected: Set(entries.map { MiniAppID($0.id) }), providers: providers)
        do {
            try await plan.apply()
            XCTFail("Expected failure")
        } catch let error as MiniAppRestoreFailure {
            XCTAssertEqual(error.completed, [MiniAppID("a")])
            XCTAssertEqual(error.failed, MiniAppID("b"))
        }
        let applied = await recorder.values
        XCTAssertEqual(applied, ["a"])
    }
}
