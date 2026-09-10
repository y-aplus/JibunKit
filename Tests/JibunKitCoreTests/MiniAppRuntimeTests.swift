import XCTest
import JibunKitCore

final class MiniAppRuntimeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRestoreWaitsForAsyncResourceReleaseBeforeApplyingAndResuming() async throws {
        let runtime = MiniAppRuntime()
        let other = MiniAppRuntime()
        let gate = RuntimeGate()
        let events = RuntimeEvents()
        let entered = expectation(description: "Connection closing")
        let otherWorked = expectation(description: "Other owner progressed")
        try runtime.onShutdownAsync {
            events.values.append("closing")
            await gate.wait(entered: entered)
            events.values.append("closed")
        }
        let owner = MiniAppID("a")
        let coordinator = MiniAppRestoreCoordinator()
        let lifecycle = MiniAppRestoreLifecycle(stop: { await runtime.shutdown() }, resume: {
            await MainActor.run { events.values.append("resumed") }
        })
        let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {
            await MainActor.run { events.values.append("applied") }
        }])
        let restoring = Task { try await plan.apply(lifecycles: [owner: lifecycle], coordinator: coordinator) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(events.values, ["closing"])
        XCTAssertThrowsError(try runtime.start {})
        let task = try other.start { otherWorked.fulfill() }
        await fulfillment(of: [otherWorked], timeout: 5)
        await task.value
        do {
            try await plan.apply(lifecycles: [owner: lifecycle], coordinator: coordinator)
            XCTFail("Second restore must not overlap connection release")
        } catch let error as MiniAppRestoreCoordinator.Conflict { XCTAssertEqual(error.owners, [owner]) }
        await gate.release()
        try await restoring.value
        XCTAssertEqual(events.values, ["closing", "closed", "applied", "resumed"])
        await other.shutdown()
    }

    @MainActor
    func testDeinitializationAwaitsAsyncCleanupBeforeLaterResourceRelease() async throws {
        var runtime: MiniAppRuntime? = MiniAppRuntime()
        weak var reference = runtime
        let gate = RuntimeGate()
        let events = RuntimeEvents()
        let entered = expectation(description: "Async cleanup entered")
        let finished = expectation(description: "Cleanup sequence finished")
        try runtime?.onShutdown { events.values.append("final"); finished.fulfill() }
        try runtime?.onShutdownAsync {
            events.values.append("async started")
            await gate.wait(entered: entered)
            events.values.append("async ended")
        }
        runtime = nil
        XCTAssertNil(reference)
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(events.values, ["async started"])
        await gate.release()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(events.values, ["async started", "async ended", "final"])
    }

    @MainActor
    func testAsyncCleanupIsAwaitedInOrderAndOtherRuntimeCanFinish() async throws {
        let runtime = MiniAppRuntime()
        let other = MiniAppRuntime()
        let events = RuntimeEvents()
        let gate = RuntimeGate()
        let entered = expectation(description: "Async cleanup entered")
        try runtime.onShutdown { events.values.append("first registered") }
        try runtime.onShutdownAsync {
            events.values.append("async started")
            await gate.wait(entered: entered)
            events.values.append("async ended")
        }
        try runtime.onShutdown { events.values.append("last registered") }
        let shutdown = Task { await runtime.shutdown(); events.values.append("returned") }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(runtime.isClosed)
        XCTAssertThrowsError(try runtime.onShutdownAsync {})
        XCTAssertEqual(events.values, ["last registered", "async started"])
        try other.onShutdown { events.values.append("other ended") }
        await other.shutdown()
        let joined = Task { await runtime.shutdown() }
        await gate.release()
        await shutdown.value
        await joined.value
        XCTAssertEqual(events.values, ["last registered", "async started", "other ended", "async ended", "first registered", "returned"])
    }

    @MainActor
    func testAdmissionClosesBeforeSlowTaskCleanupAndConcurrentShutdownWaits() async throws {
        let runtime = MiniAppRuntime()
        let events = RuntimeEvents()
        let gate = RuntimeGate()
        let started = expectation(description: "Running")
        let cleaning = expectation(description: "Cancellation cleanup entered")
        let channel = AsyncStream<Void>.makeStream()
        try runtime.onShutdown { events.values.append("resource released") }
        try runtime.start {
            started.fulfill()
            for await _ in channel.stream { }
            await gate.wait(entered: cleaning)
            await MainActor.run { events.values.append("task finished") }
        }
        await fulfillment(of: [started], timeout: 5)
        let shutdown = Task { await runtime.shutdown(); events.values.append("first returned") }
        await fulfillment(of: [cleaning], timeout: 5)
        XCTAssertTrue(runtime.isClosed)
        XCTAssertThrowsError(try runtime.start { XCTFail("Work admitted during shutdown") })
        XCTAssertThrowsError(try runtime.onShutdown { XCTFail("Cleanup admitted during shutdown") })
        XCTAssertTrue(events.values.isEmpty, "Resources must remain owned while task cleanup is pending")
        let otherShutdown = Task { await runtime.shutdown(); events.values.append("second returned") }
        await gate.release()
        await shutdown.value
        await otherShutdown.value
        XCTAssertEqual(Array(events.values.prefix(2)), ["task finished", "resource released"])
        XCTAssertEqual(Set(events.values.suffix(2)), ["first returned", "second returned"])
    }

    @MainActor
    func testOwnerDeinitializationCancelsWorkBeforeResourceCleanup() async throws {
        var runtime: MiniAppRuntime? = MiniAppRuntime()
        weak var weakRuntime = runtime
        let started = expectation(description: "Running")
        let cleaned = expectation(description: "Resource released")
        let events = RuntimeEvents()
        let channel = AsyncStream<Void>.makeStream()
        try runtime?.onShutdown { events.values.append("resource released"); cleaned.fulfill() }
        try runtime?.start {
            started.fulfill()
            for await _ in channel.stream { }
            await MainActor.run { events.values.append("task finished") }
        }
        await fulfillment(of: [started], timeout: 5)
        runtime = nil
        XCTAssertNil(weakRuntime)
        await fulfillment(of: [cleaned], timeout: 5)
        XCTAssertEqual(events.values, ["task finished", "resource released"])
    }

    @MainActor
    func testShutdownClosesAdmissionWaitsForTasksAndReleasesOnlyOwnedResources() async throws {
        let first = MiniAppRuntime()
        let second = MiniAppRuntime()
        let timer = MiniAppIdleTimer { _ in }
        let firstLease = timer.preventSleep(for: MiniAppID("first"))
        let secondLease = timer.preventSleep(for: MiniAppID("second"))
        let events = RuntimeEvents()
        try first.onShutdown { events.values.append("resource"); firstLease.release() }
        try first.onShutdown { events.values.append("last registered") }
        try second.onShutdown { secondLease.release() }
        let started = expectation(description: "Task running")
        let channel = AsyncStream<Void>.makeStream()
        let operation = try first.start {
            started.fulfill()
            for await _ in channel.stream { }
            await MainActor.run { events.values.append("task ended") }
        }
        await fulfillment(of: [started], timeout: 5)
        async let a: Void = first.shutdown()
        async let b: Void = first.shutdown()
        _ = await (a, b)
        await operation.value
        XCTAssertEqual(events.values, ["task ended", "last registered", "resource"])
        XCTAssertEqual(timer.activeOwners, [MiniAppID("second")])
        XCTAssertThrowsError(try first.start { XCTFail("Closed runtime started work") })
        XCTAssertThrowsError(try first.onShutdown { XCTFail("Closed runtime accepted cleanup") })
        XCTAssertFalse(second.isClosed)
        await second.shutdown()
        XCTAssertTrue(timer.activeOwners.isEmpty)
    }
}

@MainActor
private final class RuntimeEvents { var values: [String] = [] }

private actor RuntimeGate {
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
