import XCTest
import JibunKitCore

final class MiniAppFeatureAdmissionTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testDisabledOwnerCannotStartWhileOtherOwnerRemainsUsable() async throws {
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        let b = MiniAppFeatureLifetime(id: MiniAppID("b"))
        a.setStartAllowed(false)
        do { try await a.start(); XCTFail("Disabled owner started") }
        catch MiniAppFeatureLifetime.Failure.startsDisabled { }
        XCTAssertNil(a.runtime)
        try await b.start()
        XCTAssertEqual(b.state, .running)
        a.setStartAllowed(true)
        try await a.start()
        a.setStartAllowed(false)
        let old = try XCTUnwrap(a.runtime)
        XCTAssertFalse(old.isClosed, "Closing admission alone does not prove task/resource release")
        await a.stop()
        XCTAssertTrue(old.isClosed)
        XCTAssertEqual(b.state, .running)
        await b.stop()
    }

    @MainActor
    func testDisablingDuringRestoreDoesNotResurrectOwner() async throws {
        let a = MiniAppFeatureLifetime(id: MiniAppID("a"))
        try await a.start()
        let plan = try MiniAppRestorePlan(prepared: [a.id: MiniAppPreparedRestore {
            await a.setStartAllowed(false)
        }])
        try await plan.apply(lifecycles: [a.id: a.restoreLifecycle], coordinator: MiniAppRestoreCoordinator())
        XCTAssertFalse(a.isStartAllowed)
        XCTAssertEqual(a.state, .stopped)
        XCTAssertNil(a.runtime)
        a.setStartAllowed(true)
        try await a.start()
        XCTAssertEqual(a.state, .running)
        await a.stop()
    }
}
