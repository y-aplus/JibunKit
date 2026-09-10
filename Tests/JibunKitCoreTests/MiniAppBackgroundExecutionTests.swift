import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBackgroundExecutionTests: XCTestCase {
    func testOwnersAndOperationsEndIndependentlyAndOnlyOnce() throws {
        let provider = BackgroundAssertionSpy()
        let a = MiniAppBackgroundExecution(context: context("feature-a"), provider: provider)
        let b = MiniAppBackgroundExecution(context: context("feature-b"), provider: provider)
        let aLease = try XCTUnwrap(a.begin(operation: "save"))
        let bLease = try XCTUnwrap(b.begin(operation: "save"))

        XCTAssertEqual(provider.names, ["jibunkit.feature-a.save", "jibunkit.feature-b.save"])
        aLease.end()
        aLease.end()

        XCTAssertTrue(aLease.isEnded)
        XCTAssertFalse(bLease.isEnded)
        XCTAssertEqual(provider.ended, [0])
        XCTAssertEqual(b.activeOperationCount, 1)
    }

    func testExpirationCleansUpOnlyItsOperationAndPreventsDoubleEnd() throws {
        let provider = BackgroundAssertionSpy()
        let a = MiniAppBackgroundExecution(context: context("feature-a"), provider: provider)
        let b = MiniAppBackgroundExecution(context: context("feature-b"), provider: provider)
        var cleanups: [String] = []
        let aLease = try XCTUnwrap(a.begin(operation: "upload") { cleanups.append("a") })
        let bLease = try XCTUnwrap(b.begin(operation: "upload") { cleanups.append("b") })

        provider.expire(0)
        aLease.end()

        XCTAssertEqual(cleanups, ["a"])
        XCTAssertTrue(aLease.didExpire)
        XCTAssertFalse(bLease.isEnded)
        XCTAssertEqual(provider.ended, [0])
    }

    func testDeniedAssertionDoesNotAdmitOperation() throws {
        let provider = BackgroundAssertionSpy(denyNext: true)
        let execution = MiniAppBackgroundExecution(context: context("feature-a"), provider: provider)

        XCTAssertNil(try execution.begin(operation: "save"))
        XCTAssertEqual(execution.activeOperationCount, 0)
    }

    func testInlineExpirationDuringAcquisitionStillBalancesNativeToken() throws {
        let provider = BackgroundAssertionSpy(expireInline: true)
        let execution = MiniAppBackgroundExecution(context: context("feature-a"), provider: provider)
        var cleanupCount = 0

        let lease = try XCTUnwrap(execution.begin(operation: "save") { cleanupCount += 1 })

        XCTAssertTrue(lease.isEnded)
        XCTAssertTrue(lease.didExpire)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(provider.ended, [0])
    }

    func testRuntimeShutdownEndsOwnedAssertionsWithoutEndingOtherRuntime() async throws {
        let provider = BackgroundAssertionSpy()
        let runtime = MiniAppRuntime()
        let otherRuntime = MiniAppRuntime()
        let owned = try runtime.makeBackgroundExecution(context: context("feature-a"), provider: provider)
        let other = try otherRuntime.makeBackgroundExecution(context: context("feature-b"), provider: provider)
        let first = try XCTUnwrap(owned.begin(operation: "one"))
        let second = try XCTUnwrap(owned.begin(operation: "two"))
        let survivor = try XCTUnwrap(other.begin(operation: "one"))

        await runtime.shutdown()
        first.end()
        second.end()

        XCTAssertEqual(Set(provider.ended), Set([0, 1]))
        XCTAssertTrue(first.isEnded)
        XCTAssertTrue(second.isEnded)
        XCTAssertFalse(survivor.isEnded)
        XCTAssertThrowsError(try owned.begin(operation: "late"))
        await otherRuntime.shutdown()
        XCTAssertEqual(Set(provider.ended), Set([0, 1, 2]))
    }

    func testOwnerDeinitializationMarksExternalLeaseEndedAndLeavesOtherOwnerActive() async throws {
        let provider = BackgroundAssertionSpy()
        var owner: MiniAppBackgroundExecution? = MiniAppBackgroundExecution(
            context: context("feature-a"), provider: provider)
        let other = MiniAppBackgroundExecution(context: context("feature-b"), provider: provider)
        let orphanedLease = try XCTUnwrap(owner?.begin(operation: "save"))
        let otherLease = try XCTUnwrap(other.begin(operation: "save"))

        owner = nil
        for _ in 0..<10 where !orphanedLease.isEnded { await Task.yield() }
        orphanedLease.end()

        XCTAssertTrue(orphanedLease.isEnded)
        XCTAssertFalse(orphanedLease.didExpire)
        XCTAssertFalse(otherLease.isEnded)
        XCTAssertEqual(provider.ended, [0])
    }

    private func context(_ id: String) -> MiniAppContext {
        MiniAppContext(id: MiniAppID(id))
    }
}

@MainActor
private final class BackgroundAssertionSpy: MiniAppBackgroundAssertionProviding {
    var names: [String] = []
    var ended: [Int] = []
    var expirations: [Int: @MainActor @Sendable () -> Void] = [:]
    var denyNext: Bool
    var expireInline: Bool

    init(denyNext: Bool = false, expireInline: Bool = false) {
        self.denyNext = denyNext
        self.expireInline = expireInline
    }

    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> (@MainActor @Sendable () -> Void)? {
        if denyNext { denyNext = false; return nil }
        let token = names.count
        names.append(name)
        expirations[token] = expiration
        if expireInline { expiration() }
        return { [weak self] in self?.ended.append(token) }
    }

    func expire(_ token: Int) { expirations[token]?() }
}
