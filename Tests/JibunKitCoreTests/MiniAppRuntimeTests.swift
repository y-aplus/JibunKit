import XCTest
import JibunKitCore

final class MiniAppRuntimeTests: XCTestCase, @unchecked Sendable {
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
