import XCTest
import JibunKitCore

final class MiniAppIdleTimerTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testEndingOneOwnerOrOperationPreservesRemainingRequests() {
        var changes: [Bool] = []
        let timer = MiniAppIdleTimer { changes.append($0) }
        let a = MiniAppID("first")
        let b = MiniAppID("second")
        let first = timer.preventSleep(for: a)
        let otherOperation = timer.preventSleep(for: a)
        let second = timer.preventSleep(for: b)
        XCTAssertEqual(changes, [true])
        first.release()
        first.release()
        XCTAssertEqual(timer.activeOwners, [a, b])
        otherOperation.release()
        XCTAssertEqual(timer.activeOwners, [b])
        XCTAssertEqual(changes, [true])
        second.release()
        XCTAssertEqual(changes, [true, false])
        let later = timer.preventSleep(for: b)
        later.release()
        XCTAssertEqual(changes, [true, false, true, false])
    }

    @MainActor
    func testReleasedOwnerEventuallyEndsItsRequest() async {
        let ended = expectation(description: "Lease deinitialization updates timer")
        let timer = MiniAppIdleTimer { disabled in if !disabled { ended.fulfill() } }
        var lease: MiniAppIdleTimerLease? = timer.preventSleep(for: MiniAppID("first"))
        XCTAssertNotNil(lease)
        lease = nil
        await fulfillment(of: [ended], timeout: 5)
        XCTAssertTrue(timer.activeOwners.isEmpty)
    }
}
