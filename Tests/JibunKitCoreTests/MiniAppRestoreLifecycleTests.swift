import XCTest
@testable import JibunKitCore

final class MiniAppRestoreLifecycleTests: XCTestCase, @unchecked Sendable {
    private enum Fault: Error, Equatable { case stop, restore, resume }

    func testStopApplyResumeAndFailurePathsDoNotTouchUnselectedOwner() async throws {
        for failure in [nil, Fault.stop, .restore, .resume] {
            let events = RestoreEvents()
            let owner = MiniAppID("first")
            let lifecycle = MiniAppRestoreLifecycle(stop: {
                await events.append("stop")
                if failure == .stop { throw Fault.stop }
            }, resume: {
                await events.append("resume")
                if failure == .resume { throw Fault.resume }
            })
            let plan = try MiniAppRestorePlan(prepared: [owner: MiniAppPreparedRestore {
                await events.append("apply")
                if failure == .restore { throw Fault.restore }
            }])
            let unrelated = MiniAppRestoreLifecycle(stop: { XCTFail("Unselected owner stopped") },
                                                    resume: { XCTFail("Unselected owner resumed") })
            do {
                try await plan.apply(lifecycles: [owner: lifecycle, MiniAppID("other"): unrelated])
                XCTAssertNil(failure)
            } catch let error as MiniAppRestoreFailure {
                XCTAssertNotNil(failure)
                XCTAssertEqual(error.failed, owner)
                XCTAssertTrue(error.completed.isEmpty)
                let expected: MiniAppRestoreFailure.Stage = failure == .stop ? .stop : failure == .resume ? .resume : .apply
                XCTAssertEqual(error.stage, expected)
            }
            let observed = await events.values
            XCTAssertEqual(observed, failure == .stop ? ["stop"] : ["stop", "apply", "resume"])
        }
    }

    func testRestoreAndResumeFailuresAreBothPreserved() async throws {
        let lifecycle = MiniAppRestoreLifecycle(stop: {}, resume: { throw Fault.resume })
        do {
            try await lifecycle.perform { throw Fault.restore }
            XCTFail("Expected both failures")
        } catch let error as MiniAppRestoreLifecycle.Failure {
            XCTAssertNotNil(error.restoreReason)
            XCTAssertFalse(error.resumeReason.isEmpty)
        }
    }

    func testPlanPreservesCombinedFailureAndDoesNotRunLaterOwner() async throws {
        let owner = MiniAppID("a")
        let plan = try MiniAppRestorePlan(prepared: [
            owner: MiniAppPreparedRestore { throw Fault.restore },
            MiniAppID("b"): MiniAppPreparedRestore { XCTFail("Later owner must remain untouched") }
        ])
        do {
            try await plan.apply(lifecycles: [owner: MiniAppRestoreLifecycle(stop: {}, resume: { throw Fault.resume })])
            XCTFail("Expected failure")
        } catch let error as MiniAppRestoreFailure {
            XCTAssertEqual(error.stage, .applyAndResume)
            XCTAssertEqual(error.failed, owner)
            XCTAssertTrue(error.completed.isEmpty)
            XCTAssertTrue(error.reason.contains("runtime resume failed"))
        }
    }
}

private actor RestoreEvents {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
