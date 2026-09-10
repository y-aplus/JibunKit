import Foundation
import SQLite3
import XCTest
import JibunKitCore

/// Uses the native engine and its WAL/backup operations, not a database substitute.
final class MiniAppSQLiteIsolationTests: XCTestCase {
    func testSameDatabaseAndWALNamesStaySeparateAcrossReopenAndOwnerDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try files("database-a", root: root)
        let b = try files("database-b", root: root)
        let aURL = try a.fileURL(named: "store.sqlite")
        let bURL = try b.fileURL(named: "store.sqlite")
        let first = try NativeSQLiteFixture(aURL)
        let second = try NativeSQLiteFixture(bURL)
        try first.exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(11)")
        try second.exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(22)")
        XCTAssertNotEqual(aURL, bURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aURL.path + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bURL.path + "-wal"))
        let reader = try NativeSQLiteFixture(aURL)
        XCTAssertEqual(try reader.scalar("SELECT value FROM entry"), 11)
        try reader.close()
        try first.close()
        // All A connections are closed before removing A's owned directory.
        try FileManager.default.removeItem(at: a.directoryURL)
        XCTAssertEqual(try second.scalar("SELECT value FROM entry"), 22)
        try second.exec("UPDATE entry SET value=23")
        try second.close()
        let reopened = try NativeSQLiteFixture(bURL)
        XCTAssertEqual(try reopened.scalar("SELECT value FROM entry"), 23)
        try reopened.close()
        try a.prepareDirectory()
        let recreated = try NativeSQLiteFixture(aURL)
        XCTAssertEqual(try recreated.scalar("SELECT count(*) FROM sqlite_master WHERE name='entry'"), 0)
        try recreated.close()
    }

    func testNativeBackupIncludesCommittedWALAndRestoreChangesOnlyItsOwner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try files("database-a", root: root)
        let b = try files("database-b", root: root)
        let first = try NativeSQLiteFixture(a.fileURL(named: "store.sqlite"))
        let second = try NativeSQLiteFixture(b.fileURL(named: "store.sqlite"))
        try first.exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(31)")
        try second.exec("CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(42)")
        let snapshot = try NativeSQLiteFixture(a.fileURL(named: "snapshot.sqlite"))
        try snapshot.copyDatabase(from: first)
        XCTAssertEqual(try snapshot.scalar("SELECT value FROM entry"), 31)
        try first.exec("UPDATE entry SET value=99")
        try second.exec("UPDATE entry SET value=43")
        try first.copyDatabase(from: snapshot)
        XCTAssertEqual(try first.scalar("SELECT value FROM entry"), 31)
        XCTAssertEqual(try second.scalar("SELECT value FROM entry"), 43)
        try snapshot.close()
        try first.close()
        try second.close()
    }

    func testNativeBusyCloseMustBeHandledBeforeReplacingAStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try files("database-a", root: root)
        let database = try NativeSQLiteFixture(location.fileURL(named: "store.sqlite"))
        try database.exec("CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(5)")
        do {
            let statement = try database.prepare("SELECT value FROM entry")
            defer { sqlite3_finalize(statement) }
            XCTAssertThrowsError(try database.close()) { error in
                XCTAssertEqual((error as NSError).code, Int(SQLITE_BUSY))
            }
            // Failed close leaves this handle usable. It is not permission to replace files.
            XCTAssertEqual(try database.scalar("SELECT value FROM entry"), 5)
        }
        try database.close()
    }

    private func files(_ id: String, root: URL) throws -> MiniAppFiles {
        let files = try MiniAppFiles(context: MiniAppContext(id: MiniAppID(id)), containerURL: root)
        try files.prepareDirectory()
        return files
    }

    @MainActor
    func testBusyDatabaseCloseRecoversRuntimeWithoutApplyingOrChangingOtherOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try files("database-a", root: root)
        let b = try files("database-b", root: root)
        let first = try SQLiteRestoreOwner(a.fileURL(named: "store.sqlite"))
        let second = try SQLiteRestoreOwner(b.fileURL(named: "store.sqlite"))
        defer { first.dispose(); second.dispose() }
        let oldRuntime = first.runtime
        let statement = try first.database.prepare("SELECT value FROM entry")
        defer { sqlite3_finalize(statement) }
        let id = MiniAppID("database-a")
        let lifecycle = MiniAppRestoreLifecycle(stop: { try await first.stop() },
            resume: { XCTFail("Normal resume must not run") },
            recoverAfterFailedStop: { try await first.recover() })
        let plan = try MiniAppRestorePlan(prepared: [id: MiniAppPreparedRestore {
            XCTFail("A live database must not be replaced")
        }])
        do {
            try await plan.apply(lifecycles: [id: lifecycle], coordinator: MiniAppRestoreCoordinator())
            XCTFail("Expected native BUSY close failure")
        } catch let failure as MiniAppRestoreFailure {
            XCTAssertEqual(failure.stage, .stop)
            XCTAssertEqual(first.closeStatus, Int(SQLITE_BUSY))
        }
        XCTAssertTrue(oldRuntime.isClosed)
        XCTAssertFalse(first.runtime.isClosed)
        XCTAssertFalse(second.runtime.isClosed)
        XCTAssertFalse(first.runtime === oldRuntime)
        // Exercise new work through each owner's runtime and the still-live databases.
        let firstWork = try first.runtime.start { try? await first.write(6) }
        let otherWork = try second.runtime.start { try? await second.write(8) }
        await firstWork.value
        await otherWork.value
        XCTAssertEqual(try first.database.scalar("SELECT value FROM entry"), 6)
        XCTAssertEqual(try second.database.scalar("SELECT value FROM entry"), 8)
        await first.runtime.shutdown()
        await second.runtime.shutdown()
    }

    @MainActor
    func testAdmittedNativeTransactionPreventsRestoreAndSnapshotUntilCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try files("database-a", root: root)
        let b = try files("database-b", root: root)
        let first = try SQLiteRestoreOwner(a.fileURL(named: "store.sqlite"))
        let second = try SQLiteRestoreOwner(b.fileURL(named: "store.sqlite"))
        defer { first.dispose(); second.dispose() }
        try first.database.exec("PRAGMA journal_mode=WAL")
        let reader = try NativeSQLiteFixture(a.fileURL(named: "store.sqlite"))
        defer { try? reader.close() }
        let coordinator = MiniAppRestoreCoordinator()
        let owner = MiniAppID("database-a")
        let gate = SQLiteAccessGate()
        let writer = Task {
            try await coordinator.withStoreAccess(for: owner) {
                try await MainActor.run { try first.database.exec("BEGIN IMMEDIATE; UPDATE entry SET value=7") }
                await gate.block()
                try await MainActor.run { try first.database.exec("COMMIT") }
            }
        }
        await gate.waitUntilBlocked()
        XCTAssertEqual(try reader.scalar("SELECT value FROM entry"), 5)
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { try await first.write(9) }])
        do {
            try await plan.apply(coordinator: coordinator)
            XCTFail("Restore entered a live transaction")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        let snapshot = MiniAppBackupProvider(id: owner, export: {
            XCTFail("Snapshot entered a live transaction")
            throw MiniAppBackupError.invalidEntry
        }, prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await snapshot.exportEntry(coordinator: coordinator)
            XCTFail("Expected snapshot conflict")
        } catch is MiniAppRestoreCoordinator.Conflict {}
        try await coordinator.withStoreAccess(for: MiniAppID("database-b")) { try await second.write(8) }
        XCTAssertEqual(try second.database.scalar("SELECT value FROM entry"), 8)
        await gate.release()
        try await writer.value
        XCTAssertEqual(try reader.scalar("SELECT value FROM entry"), 7)
        try await plan.apply(coordinator: coordinator)
        XCTAssertEqual(try reader.scalar("SELECT value FROM entry"), 9)
        XCTAssertEqual(try second.database.scalar("SELECT value FROM entry"), 8)
    }
}

private actor SQLiteAccessGate {
    private var blocked = false
    private var started: CheckedContinuation<Void, Never>?
    private var finish: CheckedContinuation<Void, Never>?
    func block() async {
        await withCheckedContinuation { continuation in
            finish = continuation
            blocked = true
            started?.resume()
            started = nil
        }
    }
    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { finish?.resume(); finish = nil }
}

@MainActor
private final class SQLiteRestoreOwner {
    let database: NativeSQLiteFixture
    var runtime = MiniAppRuntime()
    var closeStatus: Int?

    init(_ url: URL) throws {
        database = try NativeSQLiteFixture(url)
        try database.exec("CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(5)")
    }
    func stop() async throws {
        await runtime.shutdown()
        do { try database.close() } catch {
            closeStatus = (error as NSError).code
            throw error
        }
    }
    func recover() throws {
        // Native BUSY leaves the connection alive; verify it before reopening admission.
        _ = try database.scalar("SELECT value FROM entry")
        runtime = MiniAppRuntime()
    }
    func write(_ value: Int) throws { try database.exec("UPDATE entry SET value=\(value)") }
    func dispose() { try? database.close() }
}

private final class NativeSQLiteFixture {
    private var handle: OpaquePointer?

    init(_ url: URL) throws {
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard status == SQLITE_OK else {
            sqlite3_close_v2(handle)
            handle = nil
            throw Self.error(status)
        }
    }

    func exec(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw Self.error(status) }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw Self.error(status) }
        return statement
    }

    func scalar(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW else { throw Self.error(status) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func copyDatabase(from source: NativeSQLiteFixture) throws {
        guard let backup = sqlite3_backup_init(handle, "main", source.handle, "main") else {
            throw Self.error(sqlite3_errcode(handle))
        }
        let status = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE else { throw Self.error(status) }
        guard finish == SQLITE_OK else { throw Self.error(finish) }
    }

    func close() throws {
        guard let handle else { return }
        let status = sqlite3_close(handle)
        guard status == SQLITE_OK else { throw Self.error(status) }
        self.handle = nil
    }

    private static func error(_ status: Int32) -> NSError {
        NSError(domain: "NativeSQLiteFixture", code: Int(status))
    }

    deinit { sqlite3_close_v2(handle) }
}
