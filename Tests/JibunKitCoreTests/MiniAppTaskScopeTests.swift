import XCTest
import JibunKitCore

final class MiniAppTaskScopeTests: XCTestCase {
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
