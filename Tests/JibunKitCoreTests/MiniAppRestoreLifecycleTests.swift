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

    func testFailedStopRecoveryPreservesBothReasonsAndDoesNotStartLaterOwner() async throws {
        let owner = MiniAppID("a")
        for recoveryFails in [false, true] {
            let events = RestoreEvents()
            let plan = try MiniAppRestorePlan(prepared: [
                owner: MiniAppPreparedRestore { XCTFail("Apply after failed stop") },
                MiniAppID("b"): MiniAppPreparedRestore { XCTFail("Later owner changed") }
            ])
            let lifecycle = MiniAppRestoreLifecycle(stop: {
                await events.append("stop")
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "store still busy"])
            }, resume: { XCTFail("Normal resume after failed stop") }, recoverAfterFailedStop: {
                await events.append("recover")
                if recoveryFails {
                    throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "connection unavailable"])
                }
            })
            do {
                try await plan.apply(lifecycles: [owner: lifecycle], coordinator: MiniAppRestoreCoordinator())
                XCTFail("Stop failure must still be reported after recovery")
            } catch let failure as MiniAppRestoreFailure {
                XCTAssertEqual(failure.stage, recoveryFails ? .stopAndRecovery : .stop)
                XCTAssertTrue(failure.reason.contains("store still busy"))
                XCTAssertEqual(failure.reason.contains("connection unavailable"), recoveryFails)
                XCTAssertEqual(failure.failed, owner)
                XCTAssertTrue(failure.completed.isEmpty)
            }
            let observed = await events.values
            XCTAssertEqual(observed, ["stop", "recover"])
        }
    }

    func testSuccessfulStopNeverUsesFailedStopRecoveryEvenWhenApplyFails() async throws {
        for applyFails in [false, true] {
            let events = RestoreEvents()
            let lifecycle = MiniAppRestoreLifecycle(stop: { await events.append("stop") },
                resume: { await events.append("resume") },
                recoverAfterFailedStop: { XCTFail("Recovery belongs only to failed stop") })
            do {
                try await lifecycle.perform {
                    await events.append("apply")
                    if applyFails { throw Fault.restore }
                }
                XCTAssertFalse(applyFails)
            } catch let failure as Fault {
                XCTAssertTrue(applyFails)
                XCTAssertEqual(failure, .restore)
            }
            let observed = await events.values
            XCTAssertEqual(observed, ["stop", "apply", "resume"])
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
