import XCTest
import JibunKitCore

final class MiniAppRuntimeTests: XCTestCase, @unchecked Sendable {
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
