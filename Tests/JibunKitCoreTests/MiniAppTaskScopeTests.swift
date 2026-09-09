import XCTest
import JibunKitCore

final class MiniAppTaskScopeTests: XCTestCase, @unchecked Sendable {
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
