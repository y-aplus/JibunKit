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
