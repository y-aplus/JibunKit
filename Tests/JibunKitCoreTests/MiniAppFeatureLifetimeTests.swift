import XCTest
import JibunKitCore

final class MiniAppFeatureLifetimeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testConcurrentStartupAndCancelledViewKeepOneOwnerAlive() async throws {
        let gate = FeatureLifetimeGate()
        let entered = expectation(description: "Configuration entered")
        let events = FeatureLifetimeEvents()
        let lifetime = MiniAppFeatureLifetime(id: MiniAppID("a")) { runtime in
            events.starts += 1
            try runtime.onShutdown { events.cleanups += 1 }
            await gate.wait(entered: entered)
        }
        let firstView = Task { try await lifetime.start() }
        await fulfillment(of: [entered], timeout: 5)
        let secondView = Task { try await lifetime.start() }
        firstView.cancel()
        XCTAssertEqual(lifetime.state, .starting)
        await gate.release()
        do { try await firstView.value; XCTFail("Cancelled waiter succeeded") }
        catch is CancellationError {}
        try await secondView.value
        XCTAssertEqual(events.starts, 1)
        XCTAssertEqual(events.cleanups, 0)
        XCTAssertEqual(lifetime.state, .running)
        let oldRuntime = try XCTUnwrap(lifetime.runtime)
        try await lifetime.start()
        XCTAssertTrue(lifetime.runtime === oldRuntime)
        await lifetime.stop()
        XCTAssertEqual(events.cleanups, 1)
    }

    @MainActor
    func testStopDuringStartupWaitsForConfigurationAndCleanup() async throws {
        let configureGate = FeatureLifetimeGate()
        let cleanupGate = FeatureLifetimeGate()
        let entered = expectation(description: "Configuring")
        let cleaning = expectation(description: "Cleaning")
        let stopRequested = expectation(description: "Stop requested")
        let lifetime = MiniAppFeatureLifetime(id: MiniAppID("a")) { runtime in
            try runtime.onShutdownAsync { await cleanupGate.wait(entered: cleaning) }
            await configureGate.wait(entered: entered)
        }
        let starting = Task { try await lifetime.start() }
        await fulfillment(of: [entered], timeout: 5)
        let stopping = Task { stopRequested.fulfill(); await lifetime.stop() }
        await fulfillment(of: [stopRequested], timeout: 5)
        await configureGate.release()
        await fulfillment(of: [cleaning], timeout: 5)
        XCTAssertEqual(lifetime.state, .stopping)
        XCTAssertNotNil(lifetime.runtime)
        await cleanupGate.release()
        await stopping.value
        do { try await starting.value; XCTFail("Explicitly stopped startup succeeded") }
        catch is CancellationError {}
        XCTAssertNil(lifetime.runtime)
        XCTAssertEqual(lifetime.state, .stopped)
    }

    @MainActor
    func testFailedConfigurationReleasesResourcesAndRetryCreatesNewRuntime() async throws {
        let events = FeatureLifetimeEvents()
        let lifetime = MiniAppFeatureLifetime(id: MiniAppID("a")) { runtime in
            events.starts += 1
            try runtime.onShutdown { events.cleanups += 1 }
            if events.starts == 1 { throw FeatureLifetimeTestFailure.failed }
        }
        do { try await lifetime.start(); XCTFail("Configuration should fail") }
        catch FeatureLifetimeTestFailure.failed {}
        guard case .failed = lifetime.state else { return XCTFail("No failure state") }
        XCTAssertNil(lifetime.runtime)
        XCTAssertEqual(events.cleanups, 1)
        try await lifetime.start()
        XCTAssertEqual(lifetime.state, .running)
        XCTAssertEqual(events.starts, 2)
        await lifetime.stop()
        XCTAssertEqual(events.cleanups, 2)
    }

    @MainActor
    func testRestoreReopensStartedOwnerAndPreservesOtherRuntime() async throws {
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        let b = MiniAppFeatureLifetime(id: MiniAppID("b"))
        try await a.start()
        try await b.start()
        let oldA = try XCTUnwrap(a.runtime)
        let oldB = try XCTUnwrap(b.runtime)
        let plan = try MiniAppRestorePlan(prepared: [a.id: MiniAppPreparedRestore {
            await MainActor.run {
                XCTAssertEqual(a.state, .stopped)
                XCTAssertTrue(oldA.isClosed)
                XCTAssertFalse(oldB.isClosed)
            }
            do { try await a.start(); XCTFail("Admitted work during restore") }
            catch MiniAppFeatureLifetime.Failure.suspendedForRestore {}
        }])
        try await plan.apply(lifecycles: [a.id: a.restoreLifecycle], coordinator: MiniAppRestoreCoordinator())
        XCTAssertEqual(a.state, .running)
        XCTAssertFalse(a.runtime === oldA)
        XCTAssertTrue(b.runtime === oldB)
        await a.stop()
        await b.stop()
    }

    @MainActor
    func testRestoreOfUnopenedFeatureDoesNotStartWork() async throws {
        let events = FeatureLifetimeEvents()
        let a = MiniAppFeatureLifetime(id: MiniAppID("a")) { _ in events.starts += 1 }
        let plan = try MiniAppRestorePlan(prepared: [a.id: MiniAppPreparedRestore {}])
        try await plan.apply(lifecycles: [a.id: a.restoreLifecycle], coordinator: MiniAppRestoreCoordinator())
        XCTAssertEqual(events.starts, 0)
        XCTAssertEqual(a.state, .stopped)
        try await a.start()
        XCTAssertEqual(events.starts, 1)
        await a.stop()
    }

    @MainActor
    func testCancellationDuringApplyStillResumesBeforeReportingFailure() async throws {
        let gate = FeatureLifetimeGate()
        let applying = expectation(description: "Applying")
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        try await a.start()
        let plan = try MiniAppRestorePlan(prepared: [a.id: MiniAppPreparedRestore {
            await gate.wait(entered: applying)
            try Task.checkCancellation()
        }])
        let lifecycle = a.restoreLifecycle
        let restoring = Task { try await plan.apply(lifecycles: [a.id: lifecycle], coordinator: MiniAppRestoreCoordinator()) }
        await fulfillment(of: [applying], timeout: 5)
        restoring.cancel()
        await gate.release()
        do { try await restoring.value; XCTFail("Cancelled apply succeeded") }
        catch let failure as MiniAppRestoreFailure { XCTAssertEqual(failure.stage, .apply) }
        XCTAssertEqual(a.state, .running)
        XCTAssertFalse(try XCTUnwrap(a.runtime).isClosed)
        await a.stop()
    }

    @MainActor
    func testExplicitStopDuringMaintenanceSuppressesAutomaticResume() async throws {
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        try await a.start()
        let plan = try MiniAppRestorePlan(prepared: [a.id: MiniAppPreparedRestore { await a.stop() }])
        try await plan.apply(lifecycles: [a.id: a.restoreLifecycle], coordinator: MiniAppRestoreCoordinator())
        XCTAssertEqual(a.state, .stopped)
        XCTAssertNil(a.runtime)
    }
}

private enum FeatureLifetimeTestFailure: Error { case failed }

@MainActor
private final class FeatureLifetimeEvents {
    var starts = 0
    var cleanups = 0
}

private actor FeatureLifetimeGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait(entered: XCTestExpectation) async {
        entered.fulfill()
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
