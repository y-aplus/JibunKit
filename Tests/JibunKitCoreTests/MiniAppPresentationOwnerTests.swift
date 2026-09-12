import XCTest
import JibunKitCore

final class MiniAppPresentationOwnerTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testCancellationEndsOnlyTheCancelledSurface() async throws {
        let runtime = MiniAppRuntime()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        try owner.connect(to: runtime)
        let events = PresentationEvents()
        let sheet = try owner.begin(.sheet) { events.values.append("sheet dismissed") }
        _ = try owner.begin(.fullScreenCover) { events.values.append("cover dismissed") }

        owner.didEnd(sheet)

        XCTAssertEqual(owner.activeKinds, [.fullScreenCover])
        XCTAssertTrue(events.values.isEmpty)
        await runtime.shutdown()
        XCTAssertEqual(events.values, ["cover dismissed"])
    }

    @MainActor
    func testShutdownAwaitsReverseOrderDismissalAndKeepsOtherOwner() async throws {
        let runtimeA = MiniAppRuntime()
        let runtimeB = MiniAppRuntime()
        let ownerA = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        let ownerB = MiniAppPresentationOwner(id: MiniAppID("feature-b"))
        try ownerA.connect(to: runtimeA)
        try ownerB.connect(to: runtimeB)
        let events = PresentationEvents()
        let gate = PresentationGate()
        let dismissalEntered = expectation(description: "UIKit dismissal entered")
        let shutdownReturned = PresentationFlag()
        _ = try ownerA.begin(.sheet) { events.values.append("sheet") }
        _ = try ownerA.begin(.uiViewController) {
            events.values.append("uikit started")
            await gate.wait(entered: dismissalEntered)
            events.values.append("uikit ended")
        }
        _ = try ownerB.begin(.sheet) { events.values.append("other") }

        let shutdown = Task {
            await runtimeA.shutdown()
            shutdownReturned.value = true
        }
        await fulfillment(of: [dismissalEntered], timeout: 5)

        XCTAssertFalse(shutdownReturned.value)
        XCTAssertEqual(ownerA.activePresentationCount, 2)
        XCTAssertEqual(ownerB.activeKinds, [.sheet])
        XCTAssertThrowsError(try ownerA.begin(.sheet) {}) { error in
            XCTAssertEqual(error as? MiniAppPresentationOwner.Failure, .notConnected)
        }
        XCTAssertThrowsError(try ownerA.connect(to: runtimeA)) { error in
            XCTAssertEqual(error as? MiniAppPresentationOwner.Failure, .alreadyConnected)
        }

        await gate.release()
        await shutdown.value
        XCTAssertEqual(events.values, ["uikit started", "uikit ended", "sheet"])
        XCTAssertEqual(ownerB.activeKinds, [.sheet])
        await runtimeB.shutdown()
        XCTAssertEqual(events.values.last, "other")
    }

    @MainActor
    func testNewRuntimeGenerationCanReconnectAfterCompletedShutdown() async throws {
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        let first = MiniAppRuntime()
        try owner.connect(to: first)
        XCTAssertThrowsError(try owner.connect(to: first))
        await first.shutdown()

        let second = MiniAppRuntime()
        try owner.connect(to: second)
        _ = try owner.begin(.sheet) {}
        XCTAssertEqual(owner.activePresentationCount, 1)
        await second.shutdown()
        XCTAssertEqual(owner.activePresentationCount, 0)
    }
}

@MainActor
private final class PresentationEvents { var values: [String] = [] }

@MainActor
private final class PresentationFlag { var value = false }

private actor PresentationGate {
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
