import Foundation
import XCTest
import JibunKitCore
@testable import CounterFeature
@testable import ReminderFeature

final class MiniAppBackupIntegrationTests: XCTestCase {
    private func stores() -> (CounterStore, ReminderStore) {
        let suite = "BackupTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (CounterStore(suiteName: suite), ReminderStore(suiteName: suite))
    }

    func testRestoreOnlySelectedFeature() async throws {
        let (counter, reminder) = stores()
        _ = try await counter.add(7)
        try await reminder.saveMessage("original")
        let backup = try await MiniAppBackup(entries: [counter.backupProvider.export(), reminder.backupProvider.export()])
        _ = try await counter.add(5)
        try await reminder.saveMessage("keep this")
        let plan = try MiniAppRestorePlan(backup: backup, selected: [.counter],
                                          providers: [counter.backupProvider, reminder.backupProvider])
        // Preparing a plan does not alter either store.
        let before = try await counter.currentValue()
        XCTAssertEqual(before, 12)
        try await plan.apply()
        let value = try await counter.currentValue()
        let message = try await reminder.currentMessage()
        XCTAssertEqual(value, 7)
        XCTAssertEqual(message, "keep this")
    }

    func testInvalidSelectedPayloadPreventsEveryApplication() async throws {
        let (counter, reminder) = stores()
        _ = try await counter.add(4)
        let good = try await counter.backupProvider.export()
        _ = try await counter.add(3)
        try await reminder.saveMessage("keep")
        let bad = MiniAppBackupEntry(id: .reminder, schemaVersion: 1, payload: Data("{}".utf8))
        let backup = try MiniAppBackup(entries: [good, bad])
        XCTAssertThrowsError(try MiniAppRestorePlan(backup: backup, selected: [.counter, .reminder],
                                                   providers: [counter.backupProvider, reminder.backupProvider]))
        let value = try await counter.currentValue()
        let message = try await reminder.currentMessage()
        XCTAssertEqual(value, 7)
        XCTAssertEqual(message, "keep")
        XCTAssertThrowsError(try counter.backupProvider.prepareRestore(bad))
    }

    func testReminderRestoreDoesNotChangeCounterAndRejectsFutureSchema() async throws {
        let (counter, reminder) = stores()
        try await reminder.saveMessage("saved")
        let entry = try await reminder.backupProvider.export()
        try await reminder.saveMessage("new")
        _ = try await counter.add(9)
        try await reminder.backupProvider.prepareRestore(entry).apply()
        let value = try await counter.currentValue()
        let message = try await reminder.currentMessage()
        XCTAssertEqual(value, 9)
        XCTAssertEqual(message, "saved")
        let future = MiniAppBackupEntry(id: .reminder, schemaVersion: 999, payload: entry.payload)
        XCTAssertThrowsError(try reminder.backupProvider.prepareRestore(future))
    }
}
