import Foundation
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppSharedRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func context(_ id: String) -> MiniAppContext { .init(id: MiniAppID(id)) }

    func testTwoOwnersShareOneSlotAndCancellationPreservesOtherOwnerAndDates() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        let b = center.refreshes(for: context("b"))
        try a.register(identifier: "sync") { _ in }
        try b.register(identifier: "sync") { _ in }
        let later = now.addingTimeInterval(200)
        let early = now.addingTimeInterval(100)
        let old = try a.submit(identifier: "sync", earliestBeginDate: later)
        let other = try b.submit(identifier: "sync", earliestBeginDate: early)
        XCTAssertEqual(scheduler.pending.count, 1)
        XCTAssertEqual(scheduler.pending["shared"]?.earliestBeginDate, early)
        let replacement = try a.submit(identifier: "sync")
        XCTAssertNotEqual(old.generation, replacement.generation)
        XCTAssertEqual(a.pendingRequests.map(\.generation), [replacement.generation])
        XCTAssertNil(scheduler.pending["shared"]?.earliestBeginDate)
        try a.cancelAllPendingRequests()
        XCTAssertEqual(scheduler.pending["shared"]?.earliestBeginDate, early)
        XCTAssertEqual(b.pendingRequests.map(\.generation), [other.generation])
        XCTAssertEqual(journal.records.map(\.owner), ["b"])
        XCTAssertTrue(scheduler.cancellations.allSatisfy { $0 == "shared" })
    }

    func testNativeRejectionIsSeparateFromDurabilityAndDoesNotCancelDirectTask() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        scheduler.pending["direct"] = .init(identifier: "direct")
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        try a.register(identifier: "sync") { _ in }
        let receipt = try a.submit(identifier: "sync")
        guard case .rejected = receipt.scheduling else { return XCTFail("OS rejection must be visible") }
        XCTAssertEqual(journal.records.map(\.generation), [receipt.generation])
        XCTAssertNotNil(scheduler.pending["direct"])
        XCTAssertTrue(scheduler.cancellations.isEmpty)
        scheduler.pending.removeValue(forKey: "direct")
        guard case .submitted = center.reconcile() else { return XCTFail("Durable work must retry") }
        XCTAssertEqual(scheduler.pending.count, 1)
        XCTAssertEqual(a.pendingRequests.map(\.generation), [receipt.generation])
    }

    func testStorageFailureDoesNotAcceptOrMutatePendingWork() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        try a.register(identifier: "sync") { _ in }
        let original = try a.submit(identifier: "sync")
        let nativeBefore = scheduler.pending
        journal.failSave = true
        XCTAssertThrowsError(try a.submit(identifier: "sync", earliestBeginDate: now))
        XCTAssertThrowsError(try a.cancelAllPendingRequests())
        XCTAssertEqual(a.pendingRequests.map(\.generation), [original.generation])
        XCTAssertEqual(journal.records.map(\.generation), [original.generation])
        XCTAssertEqual(scheduler.pending, nativeBefore)
    }

    func testBatchSnapshotsDueJobsAndWaitsForEveryCleanupIncludingAfterUnregister() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let date = now
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler, now: { date })
        let a = center.refreshes(for: context("a"))
        let b = center.refreshes(for: context("b"))
        var executions: [String: MiniAppSharedRefreshExecution] = [:]
        var expired: [String] = []
        try a.register(identifier: "sync") { task in
            executions["a"] = task
            task.onExpiration = { expired.append("a") }
            b.unregister(identifier: "sync")
        }
        try b.register(identifier: "sync") { task in
            executions["b"] = task
            task.onExpiration = { expired.append("b") }
        }
        try a.register(identifier: "future") { _ in XCTFail("Future work was delivered early") }
        try a.submit(identifier: "sync")
        try b.submit(identifier: "sync")
        try a.submit(identifier: "future", earliestBeginDate: date.addingTimeInterval(30))
        let native = scheduler.launch("shared")
        XCTAssertEqual(Set(executions.keys), ["a", "b"])
        XCTAssertEqual(journal.records.filter { $0.phase == .running }.count, 2)
        executions["a"]?.complete(success: true)
        XCTAssertTrue(native.completions.isEmpty)
        native.expire()
        native.expire()
        XCTAssertEqual(expired, ["b"])
        XCTAssertTrue(executions["b"]?.isExpired == true)
        native.expirationHandler = nil
        weak var retained = executions["b"]
        executions.removeValue(forKey: "b")
        XCTAssertNotNil(retained, "Center must retain unfinished cleanup")
        retained?.complete(success: true)
        XCTAssertEqual(native.completions, [false], "Expired native batch cannot report success")
        let completedA = try XCTUnwrap(executions["a"])
        guard case .alreadyCompleted = completedA.complete(success: true) else {
            return XCTFail("Duplicate completion must do nothing")
        }
        XCTAssertEqual(a.pendingRequests.map(\.identifier), ["future"])
        XCTAssertEqual(scheduler.pending["shared"]?.earliestBeginDate, date.addingTimeInterval(30))
    }

    func testNewGenerationAndReentrantNativeLaunchSurviveOldCompletion() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        var deliveries: [MiniAppSharedRefreshExecution] = []
        try a.register(identifier: "sync") { deliveries.append($0) }
        let old = try a.submit(identifier: "sync")
        let firstNative = scheduler.launch("shared")
        let replacement = try a.submit(identifier: "sync")
        var nextNative: RefreshNativeSpy?
        firstNative.onComplete = { nextNative = scheduler.launch("shared") }
        deliveries[0].complete(success: true)
        XCTAssertEqual(deliveries.map { $0.request.generation }, [old.generation, replacement.generation])
        XCTAssertEqual(firstNative.completions, [true])
        XCTAssertTrue(try XCTUnwrap(nextNative).completions.isEmpty)
        deliveries[0].complete(success: false)
        XCTAssertEqual(journal.records.map(\.generation), [replacement.generation])
        deliveries[1].complete(success: true)
        XCTAssertEqual(nextNative?.completions, [true])
        XCTAssertTrue(journal.records.isEmpty)
    }

    func testCrashRecoveryRetainsOldRunningAndNewPendingWithoutMisroutingUnknownOwners() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let oldCenter = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let oldA = oldCenter.refreshes(for: context("a"))
        let oldB = oldCenter.refreshes(for: context("b"))
        var oldExecution: MiniAppSharedRefreshExecution?
        try oldA.register(identifier: "sync") { oldExecution = $0 }
        try oldB.register(identifier: "sync") { _ in }
        let running = try oldA.submit(identifier: "sync")
        _ = scheduler.launch("shared")
        let pending = try oldA.submit(identifier: "sync")
        let unknown = try oldB.submit(identifier: "sync")
        // A new journal instance simulates the bytes available to a new process;
        // old process cleanup below cannot mutate this recovered journal.
        let recoveredJournal = RefreshJournalSpy(records: journal.records)
        let nextScheduler = RefreshSchedulerSpy()
        let recovered = try MiniAppSharedRefreshCenter(identifier: "shared", journal: recoveredJournal, scheduler: nextScheduler)
        let a = recovered.refreshes(for: context("a"))
        var delivered: [MiniAppSharedRefreshExecution] = []
        try a.register(identifier: "sync") { delivered.append($0) }
        guard case let .submitted(_, unresolved) = recovered.reconcile() else { return XCTFail("Expected recovered submission") }
        XCTAssertEqual(unresolved, 1)
        let native = nextScheduler.launch("shared")
        XCTAssertEqual(delivered.map { $0.request.generation }, [running.generation, pending.generation])
        XCTAssertEqual(delivered.map { $0.request.isRecovery }, [true, false])
        delivered.forEach { $0.complete(success: true) }
        XCTAssertEqual(native.completions, [true])
        XCTAssertEqual(recoveredJournal.records.map(\.generation), [unknown.generation])
        guard case let .idle(unresolved) = recovered.reconcile() else { return XCTFail("Unknown owner must not get an empty native loop") }
        XCTAssertEqual(unresolved, 1)
        oldExecution?.complete(success: true)
    }

    func testFailedLaunchPersistenceDoesNotDeliverAndFailedAcknowledgementRemainsRecoverable() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        var delivered: MiniAppSharedRefreshExecution?
        var failures = 0
        center.onError = { _ in failures += 1 }
        try a.register(identifier: "sync") { delivered = $0 }
        let receipt = try a.submit(identifier: "sync")
        journal.failSave = true
        let rejected = scheduler.launch("shared")
        XCTAssertNil(delivered)
        XCTAssertEqual(rejected.completions, [false])
        XCTAssertEqual(journal.records.map(\.phase), [.pending])
        journal.failSave = false
        _ = center.reconcile()
        let native = scheduler.launch("shared")
        journal.failSave = true
        let execution = try XCTUnwrap(delivered)
        guard case .acknowledgementFailed = execution.complete(success: true) else {
            return XCTFail("Failed durable acknowledgement must be returned")
        }
        XCTAssertEqual(native.completions, [false])
        XCTAssertEqual(failures, 2)
        XCTAssertEqual(journal.records.map(\.phase), [.running])
        XCTAssertEqual(a.pendingRequests.map(\.generation), [receipt.generation])
        XCTAssertEqual(a.pendingRequests.map(\.isRecovery), [true])
        journal.failSave = false
        let restored = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: RefreshSchedulerSpy())
        XCTAssertEqual(restored.refreshes(for: context("a")).pendingRequests.map(\.generation), [receipt.generation])
    }

    func testExpirationBeforeCleanupHandlerSetupAndFailedWorkRetryKeepSameGeneration() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        var work: MiniAppSharedRefreshExecution?
        try a.register(identifier: "sync") { work = $0 }
        let receipt = try a.submit(identifier: "sync")
        let native = scheduler.launch("shared")
        native.expire()
        var calls = 0
        work?.onExpiration = { calls += 1 }
        work?.onExpiration = { calls += 100 }
        XCTAssertEqual(calls, 1)
        work?.complete(success: false)
        XCTAssertEqual(native.completions, [false])
        XCTAssertEqual(a.pendingRequests.map(\.generation), [receipt.generation])
        let retried = scheduler.launch("shared")
        XCTAssertEqual(work?.request.generation, receipt.generation)
        XCTAssertEqual(work?.request.isRecovery, true)
        work?.complete(success: true)
        XCTAssertEqual(retried.completions, [true])
        XCTAssertTrue(journal.records.isEmpty)
    }

    func testFileJournalAndCenterRestoreOnlyUnacknowledgedGenerationsAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("first/journal.json")
        let journal = try FileSharedRefreshJournal(url: url)
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        let b = center.refreshes(for: context("b"))
        var active: [String: MiniAppSharedRefreshExecution] = [:]
        try a.register(identifier: "sync") { active["a"] = $0 }
        try b.register(identifier: "sync") { active["b"] = $0 }
        let acknowledged = try a.submit(identifier: "sync")
        let unfinished = try b.submit(identifier: "sync")
        _ = scheduler.launch("shared")
        active["a"]?.complete(success: true)
        let newer = try a.submit(identifier: "sync")
        // Snapshot the durable bytes that a restarted process would receive.
        // Separate paths let this test release old in-memory work afterward
        // without pretending that two live centers may write the same journal.
        let restartURL = root.appendingPathComponent("restarted.json")
        try Data(contentsOf: url).write(to: restartURL)
        active["b"]?.complete(success: true)
        let restartJournal = try FileSharedRefreshJournal(url: restartURL)
        let restartScheduler = RefreshSchedulerSpy()
        let restart = try MiniAppSharedRefreshCenter(identifier: "shared", journal: restartJournal, scheduler: restartScheduler)
        var recovered: [MiniAppSharedRefreshExecution] = []
        try restart.refreshes(for: context("a")).register(identifier: "sync") { recovered.append($0) }
        try restart.refreshes(for: context("b")).register(identifier: "sync") { recovered.append($0) }
        _ = restart.reconcile()
        let native = restartScheduler.launch("shared")
        XCTAssertEqual(recovered.map { $0.request.generation }, [unfinished.generation, newer.generation])
        XCTAssertFalse(recovered.contains { $0.request.generation == acknowledged.generation })
        XCTAssertEqual(recovered.map { $0.request.isRecovery }, [true, false])
        recovered[0].complete(success: true)
        XCTAssertTrue(native.completions.isEmpty)
        recovered[1].complete(success: true)
        XCTAssertEqual(native.completions, [true])
        XCTAssertTrue(try FileSharedRefreshJournal(url: restartURL).load().isEmpty)
    }

    func testCancellingPendingDoesNotFinishRunningWorkOrCancelAnotherOwner() throws {
        let journal = RefreshJournalSpy()
        let scheduler = RefreshSchedulerSpy()
        let center = try MiniAppSharedRefreshCenter(identifier: "shared", journal: journal, scheduler: scheduler)
        let a = center.refreshes(for: context("a"))
        let b = center.refreshes(for: context("b"))
        var running: MiniAppSharedRefreshExecution?
        try a.register(identifier: "sync") { running = $0 }
        try b.register(identifier: "sync") { _ in XCTFail("No second launch is requested") }
        let first = try a.submit(identifier: "sync")
        let native = scheduler.launch("shared")
        try a.submit(identifier: "sync")
        let other = try b.submit(identifier: "sync")
        try a.cancelAllPendingRequests()
        XCTAssertTrue(native.completions.isEmpty)
        XCTAssertEqual(journal.records.map(\.generation), [first.generation, other.generation])
        running?.complete(success: true)
        XCTAssertEqual(native.completions, [true])
        XCTAssertEqual(journal.records.map(\.generation), [other.generation])
        XCTAssertNotNil(scheduler.pending["shared"])
    }
}

@MainActor
private final class RefreshJournalSpy: MiniAppSharedRefreshJournaling {
    enum Failure: Error { case storage }
    var records: [MiniAppSharedRefreshRecord]
    var failSave = false
    init(records: [MiniAppSharedRefreshRecord] = []) { self.records = records }
    func load() throws -> [MiniAppSharedRefreshRecord] { records }
    func save(_ records: [MiniAppSharedRefreshRecord]) throws {
        if failSave { throw Failure.storage }
        self.records = records
    }
}

@MainActor
private final class RefreshSchedulerSpy: MiniAppBackgroundTaskScheduling {
    enum Failure: Error { case tooManyPending }
    var pending: [String: MiniAppBackgroundTaskRequest] = [:]
    var handlers: [String: @MainActor (any MiniAppBackgroundTaskNative) -> Void] = [:]
    var cancellations: [String] = []
    func register(identifier: String, kind: MiniAppBackgroundTaskKind,
                  launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void) -> Bool {
        guard handlers[identifier] == nil else { return false }
        handlers[identifier] = launch
        return true
    }
    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws {
        if pending.keys.contains(where: { $0 != request.identifier }) { throw Failure.tooManyPending }
        pending[request.identifier] = request
    }
    func cancel(identifier: String) { cancellations.append(identifier); pending.removeValue(forKey: identifier) }
    func launch(_ identifier: String) -> RefreshNativeSpy {
        let native = RefreshNativeSpy()
        guard pending.removeValue(forKey: identifier) != nil, let handler = handlers[identifier] else {
            XCTFail("Native launch must consume a submitted request for a registered identifier: \(identifier)")
            return native
        }
        handler(native)
        return native
    }
}

@MainActor
private final class RefreshNativeSpy: MiniAppBackgroundTaskNative {
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    var completions: [Bool] = []
    var onComplete: (@MainActor () -> Void)?
    func setTaskCompleted(success: Bool) { completions.append(success); onComplete?() }
    func expire() { expirationHandler?() }
}
