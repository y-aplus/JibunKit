import XCTest
@testable import JibunKitCore

final class MiniAppRestoreCoordinatorTests: XCTestCase, @unchecked Sendable {
    func testFailedStopRecoveryKeepsReservationUntilFinishedEvenAfterCancellation() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let owner = MiniAppID("a")
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { XCTFail("Failed stop applied") }])
        let lifecycle = MiniAppRestoreLifecycle(stop: { throw MiniAppBackupError.invalidEntry },
            resume: { XCTFail("Normal resume ran") }, recoverAfterFailedStop: { await gate.block() })
        let request = Task { try await plan.apply(lifecycles: [owner: lifecycle], coordinator: coordinator) }
        await gate.waitUntilBlocked()
        request.cancel()
        let snapshot = MiniAppBackupProvider(id: owner, export: {
            XCTFail("Read during partial shutdown recovery")
            throw MiniAppBackupError.invalidEntry
        }, prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await snapshot.exportEntry(coordinator: coordinator)
            XCTFail("Recovery reservation released too early")
        } catch let failure as MiniAppRestoreCoordinator.Conflict {
            XCTAssertEqual(failure.owners, [owner])
        }
        let other = try MiniAppRestorePlan(prepared: [MiniAppID("b"): MiniAppPreparedRestore {}])
        try await other.apply(coordinator: coordinator)
        await gate.release()
        do {
            try await request.value
            XCTFail("Expected failed stop")
        } catch let failure as MiniAppRestoreFailure { XCTAssertEqual(failure.stage, .stop) }
        let retry = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        try await retry.apply(coordinator: coordinator)
    }

    func testFailedAndInvalidExportsReleaseTheirOwner() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let owner = MiniAppID("a")
        let invalid = MiniAppBackupProvider(id: owner, export: {
            MiniAppBackupEntry(id: MiniAppID("wrong"), schemaVersion: 1, payload: Data())
        }, prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await invalid.exportEntry(coordinator: coordinator)
            XCTFail("Wrong owner accepted")
        } catch let error as MiniAppBackupError { XCTAssertEqual(error, .invalidEntry) }
        let failing = MiniAppFileBackupProvider(id: owner, export: { _ in throw CancellationError() },
                                               prepare: { _ in MiniAppPreparedRestore {} })
        do {
            _ = try await failing.exportEntry(to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                               coordinator: coordinator)
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let restore = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        try await restore.apply(coordinator: coordinator)
    }

    func testExportOfAnotherOwnerProceedsDuringSnapshotAndCancellationRetainsReservation() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let owner = MiniAppID("a")
        let provider = MiniAppBackupProvider(id: owner, export: {
            await gate.block()
            throw CancellationError()
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let exporting = Task { try await provider.exportEntry(coordinator: coordinator) }
        await gate.waitUntilBlocked()
        exporting.cancel()
        let other = MiniAppBackupProvider(id: MiniAppID("b"), export: {
            MiniAppBackupEntry(id: MiniAppID("b"), schemaVersion: 1, payload: Data())
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let snapshot = try await other.exportEntry(coordinator: coordinator)
        XCTAssertEqual(snapshot.id, "b")
        let restore = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        do {
            try await restore.apply(coordinator: coordinator)
            XCTFail("Live snapshot reservation was released on cancellation")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        await gate.release()
        do {
            _ = try await exporting.value
            XCTFail("Expected export cancellation")
        } catch is CancellationError {}
        try await restore.apply(coordinator: coordinator)
    }

    func testExportBlocksRestoreAndRestoreBlocksBothExportAdapters() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let owner = MiniAppID("a")
        let provider = MiniAppBackupProvider(id: owner, export: {
            await gate.block()
            return MiniAppBackupEntry(id: owner, schemaVersion: 1, payload: Data("snapshot".utf8))
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let exporting = Task { try await provider.exportEntry(coordinator: coordinator) }
        await gate.waitUntilBlocked()
        let forbidden = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { XCTFail("Restore overlapped export") }])
        do {
            try await forbidden.apply(coordinator: coordinator)
            XCTFail("Expected export conflict")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        await gate.release()
        let snapshot = try await exporting.value
        XCTAssertEqual(snapshot.payload, Data("snapshot".utf8))

        let restoringGate = RestoreCoordinatorGate()
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { await restoringGate.block() }])
        let restoring = Task { try await plan.apply(coordinator: coordinator) }
        await restoringGate.waitUntilBlocked()
        let json = MiniAppBackupProvider(id: owner, export: {
            XCTFail("JSON read during restore")
            throw MiniAppBackupError.invalidEntry
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let files = MiniAppFileBackupProvider(id: owner, export: { _ in
            XCTFail("File snapshot read during restore")
            throw MiniAppBackupError.invalidEntry
        }, prepare: { _ in MiniAppPreparedRestore {} })
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await json.exportEntry(coordinator: coordinator)
            XCTFail("Expected JSON conflict")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        do {
            _ = try await files.exportEntry(to: destination, coordinator: coordinator)
            XCTFail("Expected file conflict")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        await restoringGate.release()
        try await restoring.value
    }

    func testCancellationBetweenOwnersResumesCurrentOwnerAndPreservesCompletedReport() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        let resumed = expectation(description: "Current owner resumed")
        let plan = try MiniAppRestorePlan(prepared: [
            a: MiniAppPreparedRestore { await gate.block() },
            b: MiniAppPreparedRestore { XCTFail("Unstarted owner's data must remain unchanged") }
        ])
        let request = Task {
            try await plan.apply(lifecycles: [
                a: MiniAppRestoreLifecycle(stop: {}, resume: { resumed.fulfill() }),
                b: MiniAppRestoreLifecycle(stop: { XCTFail("Unstarted owner must keep running") },
                                          resume: { XCTFail("Unstarted owner must not restart") })
            ], coordinator: coordinator)
        }
        await gate.waitUntilBlocked()
        request.cancel()
        await gate.release()
        do {
            try await request.value
            XCTFail("Expected interruption before second owner")
        } catch let error as MiniAppRestoreFailure {
            XCTAssertEqual(error.stage, .cancelledBeforeStart)
            XCTAssertEqual(error.completed, [a])
            XCTAssertEqual(error.failed, b)
        }
        await fulfillment(of: [resumed], timeout: 2)
        let retry = try MiniAppRestorePlan(prepared: [a: MiniAppPreparedRestore {}, b: MiniAppPreparedRestore {}])
        try await retry.apply(coordinator: coordinator)
    }

    func testAlreadyCancelledRequestNeverStopsOrChangesData() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let owner = MiniAppID("a")
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { XCTFail("Cancelled request applied") }])
        let request = Task {
            await gate.block()
            try await plan.apply(lifecycles: [owner: MiniAppRestoreLifecycle(
                stop: { XCTFail("Cancelled request stopped owner") },
                resume: { XCTFail("Cancelled request resumed owner") })], coordinator: coordinator)
        }
        await gate.waitUntilBlocked()
        request.cancel()
        await gate.release()
        do {
            try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let retry = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        try await retry.apply(coordinator: coordinator)
    }

    func testCancellationDoesNotReleaseAnOperationStillUsingTheStore() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let owner = MiniAppID("a")
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { await gate.block() }])
        let request = Task { try await plan.apply(coordinator: coordinator) }
        await gate.waitUntilBlocked()
        request.cancel()
        let retry = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        do {
            try await retry.apply(coordinator: coordinator)
            XCTFail("Cancellation must not release a live operation's reservation")
        } catch let error as MiniAppRestoreCoordinator.Conflict {
            XCTAssertEqual(error.owners, [owner])
        }
        await gate.release()
        try await request.value
        try await retry.apply(coordinator: coordinator)
    }

    func testOverlappingPlansAreRejectedBeforeMutationWhileOtherOwnersProceed() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let gate = RestoreCoordinatorGate()
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        let first = try MiniAppRestorePlan(prepared: [a: MiniAppPreparedRestore { await gate.block() }])
        let running = Task { try await first.apply(coordinator: coordinator) }
        await gate.waitUntilBlocked()

        let overlapping = try MiniAppRestorePlan(prepared: [
            a: MiniAppPreparedRestore { XCTFail("Conflicting owner changed") },
            b: MiniAppPreparedRestore { XCTFail("Another selected owner changed before conflict rejection") }
        ])
        do {
            try await overlapping.apply(coordinator: coordinator)
            XCTFail("Expected conflict")
        } catch let error as MiniAppRestoreCoordinator.Conflict {
            XCTAssertEqual(error.owners, [a])
        }
        let independent = try MiniAppRestorePlan(prepared: [b: MiniAppPreparedRestore {}])
        try await independent.apply(coordinator: coordinator)
        await gate.release()
        try await running.value
        let retry = try MiniAppRestorePlan(prepared: [a: MiniAppPreparedRestore {}])
        try await retry.apply(coordinator: coordinator)
    }

    func testFailureReleasesReservation() async throws {
        let coordinator = MiniAppRestoreCoordinator()
        let owner = MiniAppID("a")
        let failing = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore { throw CancellationError() }])
        do {
            try await failing.apply(coordinator: coordinator)
            XCTFail("Expected failure")
        } catch is MiniAppRestoreFailure {}
        let retry = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {}])
        try await retry.apply(coordinator: coordinator)
    }
}

private actor RestoreCoordinatorGate {
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

    func release() {
        finish?.resume()
        finish = nil
    }
}
