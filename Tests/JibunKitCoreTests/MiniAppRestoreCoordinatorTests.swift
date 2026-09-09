import XCTest
@testable import JibunKitCore

final class MiniAppRestoreCoordinatorTests: XCTestCase, @unchecked Sendable {
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
