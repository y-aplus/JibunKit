import XCTest
import JibunKitCore

final class MiniAppSceneIdleTimerTests: XCTestCase {
    @MainActor
    func testReentrantCloseDuringNativeApplyDoesNotLeaveAnAcquiredLease() throws {
        let a = MiniAppID("first")
        var scope: MiniAppSceneIdleTimer?
        var changes: [Bool] = []
        let timer = MiniAppIdleTimer { value in
            changes.append(value)
            if value { scope?.close() }
        }
        scope = MiniAppSceneIdleTimer(owner: a, timer: timer)
        let scene = MiniAppSceneActivityDispatcher(handlers: [.init(id: a) { scope?.receive($0) }])
        scene.connect(phase: .active, selectedID: a)
        try scope?.setRequested(true)
        XCTAssertEqual(changes, [true, false])
        XCTAssertTrue(timer.activeOwners.isEmpty)
        scope = nil
    }

    @MainActor
    func testSelectionSuspendsRequestAndResumesWithoutEndingOtherOperations() throws {
        let a = MiniAppID("first"), b = MiniAppID("second")
        var changes: [Bool] = []
        let timer = MiniAppIdleTimer { changes.append($0) }
        let scope = MiniAppSceneIdleTimer(owner: a, timer: timer)
        let scene = MiniAppSceneActivityDispatcher(handlers: [.init(id: a, handler: scope.receive)])
        try scope.setRequested(true)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        scene.connect(phase: .active, selectedID: a)
        XCTAssertEqual(timer.activeOwners, [a])
        let independent = timer.preventSleep(for: b)
        scene.update(phase: .active, selectedID: b)
        XCTAssertEqual(timer.activeOwners, [b])
        XCTAssertEqual(changes, [true])
        independent.release()
        XCTAssertEqual(changes, [true, false])
        scene.update(phase: .active, selectedID: a)
        XCTAssertEqual(timer.activeOwners, [a])
        scene.update(phase: .background, selectedID: a)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        try scope.setRequested(false)
        scene.update(phase: .active, selectedID: a)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        XCTAssertEqual(changes, [true, false, true, false])
    }

    @MainActor
    func testMultipleScenesAndForeignEventsDoNotStealAnActiveRequest() throws {
        let a = MiniAppID("first"), b = MiniAppID("second")
        let timer = MiniAppIdleTimer { _ in }
        let scope = MiniAppSceneIdleTimer(owner: a, timer: timer)
        let one = MiniAppSceneActivityDispatcher(handlers: [.init(id: a, handler: scope.receive)])
        let two = MiniAppSceneActivityDispatcher(handlers: [.init(id: a, handler: scope.receive)])
        let foreign = MiniAppSceneActivityDispatcher(handlers: [.init(id: b, handler: scope.receive)])
        try scope.setRequested(true)
        foreign.connect(phase: .active, selectedID: b)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        one.connect(phase: .active, selectedID: a)
        two.connect(phase: .active, selectedID: a)
        one.disconnect()
        foreign.disconnect()
        XCTAssertEqual(timer.activeOwners, [a])
        two.update(phase: .inactive, selectedID: a)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        two.update(phase: .active, selectedID: a)
        XCTAssertEqual(timer.activeOwners, [a])
        two.disconnect()
        XCTAssertTrue(timer.activeOwners.isEmpty)
    }

    @MainActor
    func testRuntimeShutdownIsTerminalAndPreservesAnotherScope() async throws {
        let a = MiniAppID("first")
        let timer = MiniAppIdleTimer { _ in }
        let runtime = MiniAppRuntime()
        let scope = try runtime.makeSceneIdleTimer(for: a, using: timer)
        let other = MiniAppSceneIdleTimer(owner: a, timer: timer)
        let scene = MiniAppSceneActivityDispatcher(handlers: [.init(id: a) {
            scope.receive($0)
            other.receive($0)
        }])
        scene.connect(phase: .active, selectedID: a)
        try scope.setRequested(true)
        try other.setRequested(true)
        await runtime.shutdown()
        XCTAssertEqual(timer.activeOwners, [a])
        XCTAssertThrowsError(try scope.setRequested(true))
        XCTAssertThrowsError(try runtime.makeSceneIdleTimer(for: a, using: timer))
        other.close()
        XCTAssertTrue(timer.activeOwners.isEmpty)
        scene.update(phase: .inactive, selectedID: a)
        scene.update(phase: .active, selectedID: a)
        XCTAssertTrue(timer.activeOwners.isEmpty)
        scope.close()
    }
}
