import Foundation
import XCTest
import JibunKitCore

final class MiniAppRuntimeShutdownProgressTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testCancellationRequestDoesNotReportShutdownOrTaskCompletion() async throws {
        let runtime = MiniAppRuntime()
        let gate = ShutdownProgressGate()
        let entered = expectation(description: "Task entered")
        let task = try runtime.start {
            await gate.wait(entered: entered)
        }
        try runtime.onShutdown {}
        await fulfillment(of: [entered], timeout: 5)

        runtime.cancelTasks()

        XCTAssertEqual(
            runtime.shutdownProgress,
            .init(
                phase: .active,
                pendingTaskCount: 1,
                remainingCleanupCount: 1,
                startedAt: nil
            )
        )

        await gate.release()
        await task.value
        await runtime.shutdown()
        XCTAssertEqual(runtime.shutdownProgress.phase, .completed)
    }

    @MainActor
    func testProgressWaitsForTaskAndEachReverseOrderCleanupCompletion() async throws {
        let runtime = MiniAppRuntime()
        let taskGate1 = ShutdownProgressGate()
        let taskGate2 = ShutdownProgressGate()
        let cleanupGate1 = ShutdownProgressGate()
        let cleanupGate2 = ShutdownProgressGate()
        let cleanupGate3 = ShutdownProgressGate()
        let taskEntered1 = expectation(description: "First task entered")
        let taskEntered2 = expectation(description: "Second task entered")
        let cleanupEntered1 = expectation(description: "First registered cleanup entered")
        let cleanupEntered2 = expectation(description: "Second registered cleanup entered")
        let cleanupEntered3 = expectation(description: "Third registered cleanup entered")
        let shutdownInvoked = expectation(description: "Shutdown invoked")
        let events = ShutdownProgressEvents()

        let task1 = try runtime.start { await taskGate1.wait(entered: taskEntered1) }
        let task2 = try runtime.start { await taskGate2.wait(entered: taskEntered2) }
        try runtime.onShutdownAsync {
            events.values.append(1)
            await cleanupGate1.wait(entered: cleanupEntered1)
        }
        try runtime.onShutdownAsync {
            events.values.append(2)
            await cleanupGate2.wait(entered: cleanupEntered2)
        }
        try runtime.onShutdownAsync {
            events.values.append(3)
            await cleanupGate3.wait(entered: cleanupEntered3)
        }
        await fulfillment(of: [taskEntered1, taskEntered2], timeout: 5)
        XCTAssertEqual(runtime.shutdownProgress.pendingTaskCount, 2)
        XCTAssertEqual(runtime.shutdownProgress.remainingCleanupCount, 3)

        let earliestStart = Date()
        let shutdown = Task {
            shutdownInvoked.fulfill()
            await runtime.shutdown()
        }
        await fulfillment(of: [shutdownInvoked], timeout: 5)

        let waiting = runtime.shutdownProgress
        XCTAssertEqual(waiting.phase, .waitingForTasks)
        XCTAssertEqual(waiting.pendingTaskCount, 2)
        XCTAssertEqual(waiting.remainingCleanupCount, 3)
        let startedAt = try XCTUnwrap(waiting.startedAt)
        XCTAssertGreaterThanOrEqual(startedAt, earliestStart)
        XCTAssertLessThanOrEqual(startedAt, Date())

        await taskGate1.release()
        await task1.value
        await Task.yield()
        XCTAssertEqual(runtime.shutdownProgress.phase, .waitingForTasks)
        XCTAssertEqual(runtime.shutdownProgress.pendingTaskCount, 1)
        XCTAssertEqual(runtime.shutdownProgress.startedAt, startedAt)

        await taskGate2.release()
        await task2.value
        await fulfillment(of: [cleanupEntered3], timeout: 5)
        XCTAssertEqual(runtime.shutdownProgress.phase, .runningCleanups)
        XCTAssertEqual(runtime.shutdownProgress.pendingTaskCount, 0)
        XCTAssertEqual(runtime.shutdownProgress.remainingCleanupCount, 3)
        XCTAssertEqual(runtime.shutdownProgress.startedAt, startedAt)

        await cleanupGate3.release()
        await fulfillment(of: [cleanupEntered2], timeout: 5)
        XCTAssertEqual(runtime.shutdownProgress.remainingCleanupCount, 2)
        XCTAssertEqual(runtime.shutdownProgress.startedAt, startedAt)

        await cleanupGate2.release()
        await fulfillment(of: [cleanupEntered1], timeout: 5)
        XCTAssertEqual(runtime.shutdownProgress.remainingCleanupCount, 1)
        XCTAssertEqual(runtime.shutdownProgress.startedAt, startedAt)

        let joined = Task { await runtime.shutdown() }
        await cleanupGate1.release()
        await shutdown.value
        await joined.value

        XCTAssertEqual(events.values, [3, 2, 1])
        XCTAssertEqual(
            runtime.shutdownProgress,
            .init(
                phase: .completed,
                pendingTaskCount: 0,
                remainingCleanupCount: 0,
                startedAt: startedAt
            )
        )
    }
}

@MainActor
private final class ShutdownProgressEvents {
    var values: [Int] = []
}

private actor ShutdownProgressGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait(entered: XCTestExpectation) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
