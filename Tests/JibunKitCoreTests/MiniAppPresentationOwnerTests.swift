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

    @MainActor
    func testEndAndConcurrentShutdownCallsCoalesceOneDismissal() async throws {
        let runtime = MiniAppRuntime()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        try owner.connect(to: runtime)
        let gate = PresentationGate()
        let entered = expectation(description: "Dismissal entered once")
        entered.expectedFulfillmentCount = 1
        let allInvoked = expectation(description: "Dismiss all invoked")
        let shutdownInvoked = expectation(description: "Runtime shutdown invoked")
        let events = PresentationEvents()
        let allReturned = PresentationFlag()
        let shutdownReturned = PresentationFlag()
        let handle = try owner.begin(.uiViewController) {
            events.values.append("dismiss")
            await gate.wait(entered: entered)
        }

        let individual = Task { await owner.end(handle) }
        await fulfillment(of: [entered], timeout: 5)
        owner.didEnd(handle)
        XCTAssertEqual(owner.activePresentationCount, 0)
        // UI has ended, but the registered callback is still releasing resources.
        let all = Task {
            allInvoked.fulfill()
            await owner.dismissAll()
            allReturned.value = true
        }
        let runtimeShutdown = Task {
            shutdownInvoked.fulfill()
            await runtime.shutdown()
            shutdownReturned.value = true
        }
        await fulfillment(of: [allInvoked, shutdownInvoked], timeout: 5)
        XCTAssertFalse(allReturned.value)
        XCTAssertFalse(shutdownReturned.value)
        await gate.release()
        await individual.value
        await all.value
        await runtimeShutdown.value

        XCTAssertEqual(events.values, ["dismiss"])
        XCTAssertEqual(owner.activePresentationCount, 0)
    }

    @MainActor
    func testClosedRuntimeRejectsPresentationWhileOwnedTasksAreStillEnding() async throws {
        let runtime = MiniAppRuntime()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        try owner.connect(to: runtime)
        let taskGate = PresentationGate()
        let taskEntered = expectation(description: "Owned task entered")
        let shutdownInvoked = expectation(description: "Shutdown invoked")
        try runtime.start { await taskGate.wait(entered: taskEntered) }
        await fulfillment(of: [taskEntered], timeout: 5)

        let shutdown = Task {
            shutdownInvoked.fulfill()
            await runtime.shutdown()
        }
        await fulfillment(of: [shutdownInvoked], timeout: 5)

        XCTAssertTrue(runtime.isClosed)
        XCTAssertThrowsError(try owner.begin(.sheet) {}) { error in
            XCTAssertEqual(error as? MiniAppPresentationOwner.Failure, .notConnected)
        }
        await taskGate.release()
        await shutdown.value
    }

    @MainActor
    func testOldRuntimeCleanupCannotCloseReconnectedGeneration() async throws {
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        let oldRuntime = MiniAppRuntime()
        let newRuntime = MiniAppRuntime()
        let events = PresentationEvents()
        try owner.connect(to: oldRuntime)
        _ = try owner.begin(.sheet) { events.values.append("old") }
        await owner.dismissAll()
        try owner.connect(to: newRuntime)
        _ = try owner.begin(.fullScreenCover) { events.values.append("new") }

        await oldRuntime.shutdown()

        XCTAssertEqual(events.values, ["old"])
        XCTAssertEqual(owner.activeKinds, [.fullScreenCover])
        await newRuntime.shutdown()
        XCTAssertEqual(events.values, ["old", "new"])
    }

    @MainActor
    func testNavigationDismissalKeepsRuntimeConnectedForReturningFeature() async throws {
        let runtime = MiniAppRuntime()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        let other = MiniAppPresentationOwner(id: MiniAppID("feature-b"))
        let otherRuntime = MiniAppRuntime()
        try owner.connect(to: runtime)
        try other.connect(to: otherRuntime)
        let events = PresentationEvents()
        _ = try owner.begin(.sheet) { events.values.append("A ended") }
        _ = try other.begin(.sheet) { events.values.append("B ended") }
        await owner.dismissForNavigation()
        XCTAssertEqual(events.values, ["A ended"])
        XCTAssertFalse(runtime.isClosed)
        XCTAssertFalse(owner.hasPendingPresentations)
        XCTAssertEqual(other.activePresentationCount, 1)
        _ = try owner.begin(.fullScreenCover) { events.values.append("A returned") }
        await runtime.shutdown()
        XCTAssertEqual(events.values, ["A ended", "A returned"])
        await otherRuntime.shutdown()
    }

    @MainActor
    func testShutdownDuringNavigationDismissalClosesGenerationOnlyAfterAcknowledgement() async throws {
        let runtime = MiniAppRuntime()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))
        try owner.connect(to: runtime)
        let gate = PresentationGate()
        let entered = expectation(description: "Native dismissal entered")
        let events = PresentationEvents()
        _ = try owner.begin(.uiViewController) {
            events.values.append("dismiss")
            await gate.wait(entered: entered)
        }
        let navigation = Task { await owner.dismissForNavigation() }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(owner.hasPendingPresentations)
        XCTAssertThrowsError(try owner.begin(.sheet) {})
        let shutdownEntered = expectation(description: "Runtime shutdown entered")
        try runtime.onShutdown { shutdownEntered.fulfill() }
        let shutdown = Task { await runtime.shutdown() }
        await fulfillment(of: [shutdownEntered], timeout: 5)
        XCTAssertTrue(runtime.isClosed)
        XCTAssertTrue(owner.hasPendingPresentations)
        await gate.release()
        await navigation.value
        await shutdown.value
        XCTAssertEqual(events.values, ["dismiss"])
        XCTAssertFalse(owner.hasPendingPresentations)
        XCTAssertThrowsError(try owner.begin(.sheet) {})
        let restarted = MiniAppRuntime()
        try owner.connect(to: restarted)
        _ = try owner.begin(.sheet) {}
        await restarted.shutdown()
    }

    @MainActor
    func testClosedRuntimeCannotBeConnected() async {
        let runtime = MiniAppRuntime()
        await runtime.shutdown()
        let owner = MiniAppPresentationOwner(id: MiniAppID("feature-a"))

        XCTAssertThrowsError(try owner.connect(to: runtime)) { error in
            XCTAssertEqual(error as? MiniAppPresentationOwner.Failure, .runtimeClosed)
        }
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
