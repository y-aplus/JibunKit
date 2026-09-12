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

    func testOwnedRemovalDefaultsReloadOtherOwnerAndExistingBackupsRemainCompatible() async throws {
        let suite = "RemovalTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let counter = CounterStore(suiteName: suite)
        let reminder = ReminderStore(suiteName: suite)
        _ = try await counter.add(7)
        _ = try await reminder.saveMessage("keep reminder")
        let counterBackup = try await counter.backupProvider.export()
        let reminderBackup = try await reminder.backupProvider.export()

        try await counter.removalProvider.removeData()
        let reloadedCounter = try await CounterStore(suiteName: suite).currentValue()
        let preservedReminder = try await ReminderStore(suiteName: suite).currentMessage()
        XCTAssertEqual(reloadedCounter, 0)
        XCTAssertEqual(preservedReminder, "keep reminder")
        try await counter.backupProvider.prepareRestore(counterBackup).apply()
        let restoredCounter = try await CounterStore(suiteName: suite).currentValue()
        XCTAssertEqual(restoredCounter, 7)

        try await reminder.removalProvider.removeData()
        let preservedCounter = try await CounterStore(suiteName: suite).currentValue()
        let reloadedReminder = try await ReminderStore(suiteName: suite).currentMessage()
        XCTAssertEqual(preservedCounter, 7)
        XCTAssertEqual(reloadedReminder, "")
        try await reminder.backupProvider.prepareRestore(reminderBackup).apply()
        let restoredReminder = try await ReminderStore(suiteName: suite).currentMessage()
        XCTAssertEqual(restoredReminder, "keep reminder")
    }

    func testCancellationBeforeRemovalCallbackPreservesBothOwners() async throws {
        let suite = "CancelledRemovalTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let counter = CounterStore(suiteName: suite)
        let reminder = ReminderStore(suiteName: suite)
        _ = try await counter.add(9)
        _ = try await reminder.saveMessage("unchanged")
        let gate = RemovalGate()
        let request = Task {
            await gate.block()
            try await MiniAppRestoreCoordinator().withStoreMaintenance(for: .counter) {
                try await counter.removalProvider.removeData()
            }
        }
        await gate.waitUntilBlocked()
        request.cancel()
        await gate.release()
        do { try await request.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let value = try await CounterStore(suiteName: suite).currentValue()
        let message = try await ReminderStore(suiteName: suite).currentMessage()
        XCTAssertEqual(value, 9)
        XCTAssertEqual(message, "unchanged")
    }
}

private actor RemovalGate {
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
