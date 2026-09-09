import XCTest
import JibunKitCore

final class MiniAppTaskScopeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testJoinWaitsForCleanupWithoutCancellingWorkStartedLater() async {
        let scope = MiniAppTaskScope()
        let oldInput = AsyncStream<Void>.makeStream()
        let newInput = AsyncStream<Void>.makeStream()
        let cleaning = expectation(description: "Old operation has reached cleanup")
        let joined = expectation(description: "Original batch has finished")
        let cleanup = CleanupGate()
        let newResult = CancellationResult()
        scope.start {
            for await _ in oldInput.stream { }
            cleaning.fulfill()
            await cleanup.wait()
        }
        var joinReturned = false
        let join = Task { @MainActor in
            await scope.cancelAllAndWait()
            joinReturned = true
            joined.fulfill()
        }
        await fulfillment(of: [cleaning], timeout: 5)
        XCTAssertFalse(joinReturned, "Cancellation request is not completion")
        let later = scope.start {
            for await _ in newInput.stream { }
            await newResult.record(Task.isCancelled)
        }
        await cleanup.release()
        await fulfillment(of: [joined], timeout: 5)
        let pending = await newResult.value
        XCTAssertNil(pending, "The later batch must still be running")
        newInput.continuation.finish()
        oldInput.continuation.finish()
        await later.value
        await join.value
        let completed = await newResult.value
        XCTAssertEqual(completed, false)
    }

    @MainActor
    func testCancelAndWaitObservesEveryOwnedOperationCompletion() async {
        let scope = MiniAppTaskScope()
        let first = AsyncStream<Void>.makeStream()
        let second = AsyncStream<Void>.makeStream()
        let started = expectation(description: "Both owned operations are running")
        started.expectedFulfillmentCount = 2
        let firstResult = CancellationResult()
        let secondResult = CancellationResult()
        scope.start {
            started.fulfill()
            for await _ in first.stream { }
            await firstResult.record(Task.isCancelled)
        }
        scope.start {
            started.fulfill()
            for await _ in second.stream { }
            await secondResult.record(Task.isCancelled)
        }
        await fulfillment(of: [started], timeout: 5)
        await scope.cancelAllAndWait()
        let a = await firstResult.value
        let b = await secondResult.value
        XCTAssertEqual(a, true)
        XCTAssertEqual(b, true)
        // Joining an already completed batch must also return.
        await scope.cancelAllAndWait()
    }

    @MainActor
    func testRunningTaskDoesNotRetainScopeAndOwnerReleaseRequestsCleanup() async {
        var scope: MiniAppTaskScope? = MiniAppTaskScope()
        weak var releasedScope = scope
        let input = AsyncStream<Void>.makeStream()
        let started = expectation(description: "Operation has started")
        let finished = expectation(description: "Operation observes cancellation and finishes")
        let result = CancellationResult()
        let task = scope!.start {
            started.fulfill()
            for await _ in input.stream { }
            await result.record(Task.isCancelled)
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 5)
        scope = nil
        XCTAssertNil(releasedScope, "Scope must not be retained by its own running task")
        await fulfillment(of: [finished], timeout: 5)
        let cancelled = await result.value
        XCTAssertEqual(cancelled, true)
        input.continuation.finish()
        await task.value
    }

    @MainActor
    func testRunningCancellationFinishesOnlyItsOwnerWhileOtherWorkContinues() async {
        let first = MiniAppTaskScope()
        let second = MiniAppTaskScope()
        let firstInput = AsyncStream<Void>.makeStream()
        let secondInput = AsyncStream<Void>.makeStream()
        let started = expectation(description: "Both owners have running work")
        started.expectedFulfillmentCount = 2
        let firstFinished = expectation(description: "Cancelled owner finishes cleanup")
        let firstResult = CancellationResult()
        let secondResult = CancellationResult()
        let a = first.start {
            started.fulfill()
            for await _ in firstInput.stream { }
            await firstResult.record(Task.isCancelled)
            firstFinished.fulfill()
        }
        let b = second.start {
            started.fulfill()
            for await _ in secondInput.stream { }
            await secondResult.record(Task.isCancelled)
        }
        await fulfillment(of: [started], timeout: 5)
        first.cancelAll()
        await fulfillment(of: [firstFinished], timeout: 5)
        let cancelled = await firstResult.value
        let stillRunning = await secondResult.value
        XCTAssertEqual(cancelled, true)
        XCTAssertNil(stillRunning, "The other owner's operation must remain active")
        // Complete the second operation through its normal input, not cancellation.
        firstInput.continuation.finish()
        secondInput.continuation.finish()
        await a.value
        await b.value
        let completedNormally = await secondResult.value
        XCTAssertEqual(completedNormally, false)
    }

    @MainActor
    func testCancellationIsScopedAndDoesNotCancelSubsequentWork() async {
        let first = MiniAppTaskScope()
        let second = MiniAppTaskScope()
        let cancelled = CancellationResult()
        let unaffected = CancellationResult()
        // The main actor cannot execute the queued task bodies until this test
        // suspends, so cancellation does not depend on sleeps or scheduling luck.
        let a = first.start { await cancelled.record(Task.isCancelled) }
        let b = second.start { await unaffected.record(Task.isCancelled) }
        first.cancelAll()
        await a.value
        await b.value
        let aResult = await cancelled.value
        let bResult = await unaffected.value
        XCTAssertEqual(aResult, true)
        XCTAssertEqual(bResult, false)
        let resumed = CancellationResult()
        let next = first.start { await resumed.record(Task.isCancelled) }
        await next.value
        let nextResult = await resumed.value
        XCTAssertEqual(nextResult, false)
    }

    @MainActor
    func testReleasingOwnerCancelsItsPendingWork() async {
        var scope: MiniAppTaskScope? = MiniAppTaskScope()
        let result = CancellationResult()
        let task = scope!.start { await result.record(Task.isCancelled) }
        scope = nil
        await task.value
        let cancelled = await result.value
        XCTAssertEqual(cancelled, true)
    }
}

private actor CancellationResult {
    private(set) var value: Bool?
    func record(_ cancelled: Bool) { value = cancelled }
}

private actor CleanupGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
