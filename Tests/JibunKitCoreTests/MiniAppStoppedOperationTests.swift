import Foundation
import XCTest
import JibunKitCore

final class MiniAppStoppedOperationTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRestartWaitsForDrainAndStoppedCleanupWhileOtherOwnerRuns() async throws {
        let events = StoppedOperationEvents()
        let writerGate = StoppedOperationGate()
        let cleanupGate = StoppedOperationGate()
        let writerEntered = expectation(description: "Writer entered")
        let writerCancelled = expectation(description: "Writer received cancellation")
        let cleanupEntered = expectation(description: "Stopped cleanup entered")
        let restartRequested = expectation(description: "Restart requested")
        let a = MiniAppFeatureLifetime(id: MiniAppID("a")) { runtime in
            events.starts += 1
            if events.starts == 1 {
                try runtime.start {
                    await withTaskCancellationHandler {
                        await writerGate.wait(entered: writerEntered)
                    } onCancel: { writerCancelled.fulfill() }
                }
            }
        }
        let b = MiniAppFeatureLifetime(id: MiniAppID("b"))
        try await a.start()
        try await b.start()
        let otherRuntime = try XCTUnwrap(b.runtime)
        await fulfillment(of: [writerEntered], timeout: 5)
        let operation = Task {
            try await a.withStoppedOperation {
                events.cleanupEntered = true
                XCTAssertNil(a.runtime)
                await cleanupGate.wait(entered: cleanupEntered)
                return 42
            }
        }
        await fulfillment(of: [writerCancelled], timeout: 5)
        XCTAssertFalse(events.cleanupEntered, "Cancellation is not writer completion")
        let restart = Task {
            restartRequested.fulfill()
            try await a.start()
        }
        await fulfillment(of: [restartRequested], timeout: 5)
        XCTAssertEqual(events.starts, 1)
        await writerGate.release()
        await fulfillment(of: [cleanupEntered], timeout: 5)
        XCTAssertEqual(events.starts, 1, "Stopping work alone must not release the restart boundary")
        XCTAssertFalse(otherRuntime.isClosed)
        do {
            try await a.withStoppedOperation { XCTFail("Overlapping cleanup admitted") }
            XCTFail("Expected busy cleanup")
        } catch MiniAppFeatureLifetime.Failure.stoppedOperationInProgress {}
        await cleanupGate.release()
        let result = try await operation.value
        XCTAssertEqual(result, 42)
        try await restart.value
        XCTAssertEqual(events.starts, 2)
        XCTAssertEqual(a.state, .running)
        XCTAssertTrue(b.runtime === otherRuntime)
        await a.stop()
        await b.stop()
    }

    @MainActor
    func testCancelledCleanupKeepsManagementWaitingAndCannotReenableRemovedOwner() async throws {
        let suite = "MiniAppStoppedOperationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let events = StoppedOperationEvents()
        let gate = StoppedOperationGate()
        let entered = expectation(description: "Stopped cleanup owns maintenance")
        let cancellation = expectation(description: "Cleanup cancelled")
        let removalRequested = expectation(description: "Removal requested")
        let coordinator = MiniAppRestoreCoordinator()
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        let b = MiniAppFeatureLifetime(id: MiniAppID("b"))
        let manager = MiniAppManagement(registrations: [
            .init(id: a.id, lifetime: a, removal: .init(id: a.id, dataDescription: "A") {
                await MainActor.run { events.deleted = true }
            }),
            .init(id: b.id, lifetime: b)
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        try await a.start()
        try await b.start()
        let cleanup = Task {
            try await a.withStoppedOperation {
                try await coordinator.withStoreMaintenance(for: a.id) {
                    await withTaskCancellationHandler {
                        await gate.wait(entered: entered)
                    } onCancel: { cancellation.fulfill() }
                    try Task.checkCancellation()
                }
            }
        }
        await fulfillment(of: [entered], timeout: 5)
        let removal = Task {
            removalRequested.fulfill()
            try await manager.remove(a.id)
        }
        await fulfillment(of: [removalRequested], timeout: 5)
        cleanup.cancel()
        await fulfillment(of: [cancellation], timeout: 5)
        XCTAssertFalse(events.deleted)
        XCTAssertEqual(manager.status(for: a.id), .removing)
        let otherValue = try await coordinator.withStoreAccess(for: b.id) { 7 }
        XCTAssertEqual(otherValue, 7)
        XCTAssertEqual(b.state, .running)
        await gate.release()
        do { try await cleanup.value; XCTFail("Cancelled cleanup succeeded") }
        catch is CancellationError {}
        try await removal.value
        XCTAssertTrue(events.deleted)
        XCTAssertEqual(manager.status(for: a.id), .removed)
        do { try await a.start(); XCTFail("Cleanup reopened a removed owner") }
        catch MiniAppFeatureLifetime.Failure.startsDisabled {}
        XCTAssertNil(a.runtime)
        await b.stop()
    }
}

@MainActor
private final class StoppedOperationEvents {
    var starts = 0
    var cleanupEntered = false
    var deleted = false
}

private actor StoppedOperationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait(entered: XCTestExpectation) async {
        if released { entered.fulfill(); return }
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
