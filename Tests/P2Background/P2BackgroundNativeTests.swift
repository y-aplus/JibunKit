#if os(iOS)
import Foundation
import XCTest
@testable import JibunKit_App
@testable import JibunKitCore

@MainActor
final class P2BackgroundNativeTests: XCTestCase {
    func testDefinitionsUseLifetimeUnregisterAndExactWildcardRequirements() throws {
        let definitions = P2BackgroundProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-background-a"), MiniAppID("p2-background-b")])
        XCTAssertTrue(definitions.allSatisfy {
            $0.lifetime != nil && $0.onUnregister != nil && $0.onHostLaunch != nil
        })
        XCTAssertEqual(P2BackgroundProbe.ownerA.continuedBaseIdentifier + ".*",
                       "com.jibunkit.app.p2-background-a.export.*")
        XCTAssertEqual(P2BackgroundProbe.ownerB.continuedBaseIdentifier + ".*",
                       "com.jibunkit.app.p2-background-b.export.*")
    }

    func testStopCancelsPendingAndRejectsLateOSLaunch() async throws {
        let scheduler = P2ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let feature = P2BackgroundFeature(
            id: MiniAppID("late-a"), title: "Late A",
            continued: center.tasks(for: MiniAppContext(id: MiniAppID("late-a"))),
            work: { _ in XCTFail("Late launch must not start work") })
        try await feature.lifetime.start()
        feature.submitContinued()
        let identifier = try XCTUnwrap(scheduler.submissions.last?.identifier)

        await feature.lifetime.stop()
        XCTAssertEqual(scheduler.cancellations, [identifier])
        let native = scheduler.launch(identifier)
        XCTAssertEqual(native.completions, [false])
        XCTAssertTrue(feature.status.contains("遅着OS起動を拒否"))
    }

    func testAStopJoinsCleanupWhileBProgressAndResultSurvive() async throws {
        let scheduler = P2ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let aGate = P2WorkGate()
        let bGate = P2WorkGate()
        let a = feature("join-a", center: center, gate: aGate)
        let b = feature("join-b", center: center, gate: bGate)
        try await a.lifetime.start(); try await b.lifetime.start()
        a.submitContinued(); b.submitContinued()
        let aID = try XCTUnwrap(scheduler.submissions.first?.identifier)
        let bID = try XCTUnwrap(scheduler.submissions.last?.identifier)
        let aNative = scheduler.launch(aID)
        let bNative = scheduler.launch(bID)
        await aGate.waitUntilStarted(); await bGate.waitUntilStarted()
        aGate.progress(2, 10); bGate.progress(7, 10)
        await Task.yield()

        let stoppingA = Task { @MainActor in await a.lifetime.stop() }
        await aGate.waitUntilCancelled()
        XCTAssertEqual(a.lifetime.state, .stopping)
        XCTAssertEqual(b.progress, 7)
        XCTAssertEqual(bNative.completions, [])
        aGate.finishCancellation()
        await stoppingA.value
        XCTAssertEqual(aNative.completions, [false])
        XCTAssertEqual(b.progress, 7)

        bGate.finishSuccess()
        await bGate.waitUntilFinished()
        await Task.yield()
        XCTAssertEqual(bNative.completions, [true])
        XCTAssertEqual(b.resultCount, 1)
        XCTAssertEqual(b.progress, 7)
    }

    func testRestoreStopsCurrentGenerationWithoutRestartingWorkAndBRemains() async throws {
        let scheduler = P2ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let aGate = P2WorkGate(); let bGate = P2WorkGate()
        let a = feature("restore-a", center: center, gate: aGate)
        let b = feature("restore-b", center: center, gate: bGate)
        try await a.lifetime.start(); try await b.lifetime.start()
        a.submitContinued(); b.submitContinued()
        let aNative = scheduler.launch(try XCTUnwrap(scheduler.submissions.first?.identifier))
        let bNative = scheduler.launch(try XCTUnwrap(scheduler.submissions.last?.identifier))
        await aGate.waitUntilStarted(); await bGate.waitUntilStarted()
        bGate.progress(4, 10); await Task.yield()
        let oldGeneration = a.generation
        let restore = try XCTUnwrap(a.definition.effectiveRestoreLifecycle)
        let stopping = Task { try await restore.stop() }
        await aGate.waitUntilCancelled()
        aGate.finishCancellation()
        try await stopping.value
        try await restore.resume()

        XCTAssertEqual(a.generation, oldGeneration + 1)
        XCTAssertEqual(aNative.completions, [false])
        XCTAssertEqual(b.progress, 4)
        XCTAssertEqual(bNative.completions, [])
        XCTAssertFalse(a.status.contains("OS起動"), "Restore must not restart business work")
        bGate.finishSuccess(); await bGate.waitUntilFinished(); await Task.yield()
        XCTAssertEqual(b.resultCount, 1)
    }

    func testCancellationMustJoinBeforeNextUniqueJobStarts() async throws {
        let scheduler = P2ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let first = P2WorkGate(); let second = P2WorkGate()
        let sequence = P2WorkSequence([first, second])
        let owner = MiniAppID("next-a")
        let feature = P2BackgroundFeature(
            id: owner, title: "next-a",
            continued: center.tasks(for: MiniAppContext(id: owner)), work: sequence.work)
        try await feature.lifetime.start()
        feature.submitContinued()
        let firstID = try XCTUnwrap(scheduler.submissions.last?.identifier)
        _ = scheduler.launch(firstID)
        await first.waitUntilStarted()
        let firstGeneration = feature.generation

        let cancelling = Task { @MainActor in await feature.cancelContinued() }
        await first.waitUntilCancelled()
        feature.submitContinued()
        XCTAssertEqual(scheduler.submissions.count, 1, "No next job before cleanup joins")
        first.finishCancellation()
        await cancelling.value

        feature.submitContinued()
        let secondID = try XCTUnwrap(scheduler.submissions.last?.identifier)
        XCTAssertNotEqual(firstID, secondID)
        let secondNative = scheduler.launch(secondID)
        await second.waitUntilStarted()
        XCTAssertGreaterThan(feature.generation, firstGeneration)
        second.finishSuccess(); await second.waitUntilFinished(); await Task.yield()
        XCTAssertEqual(secondNative.completions, [true])
        XCTAssertEqual(feature.resultCount, 1)
    }

    func testOrdinaryColdLaunchHonorsDisableAndStopJoinsWithoutTouchingB() async throws {
        let continuedScheduler = P2ContinuedSchedulerSpy()
        let continuedCenter = MiniAppContinuedProcessingCenter(scheduler: continuedScheduler)
        let scheduler = P2BackgroundSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let aGate = P2BackgroundWorkGate(); let bGate = P2BackgroundWorkGate()
        let a = backgroundFeature("ordinary-a", continued: continuedCenter, gate: aGate)
        let b = backgroundFeature("ordinary-b", continued: continuedCenter, gate: bGate)
        let aTasks = center.tasks(for: MiniAppContext(id: a.id))
        let bTasks = center.tasks(for: MiniAppContext(id: b.id))
        try aTasks.register(identifier: "com.example.ordinary.a", kind: .appRefresh) {
            a.admitOrdinary($0)
        }
        try bTasks.register(identifier: "com.example.ordinary.b", kind: .processing) {
            b.admitOrdinary($0)
        }

        a.lifetime.setStartAllowed(false)
        let rejected = scheduler.launch("com.example.ordinary.a")
        await eventually { rejected.completions == [false] }
        XCTAssertFalse(aGate.started)

        a.lifetime.setStartAllowed(true)
        let aNative = scheduler.launch("com.example.ordinary.a")
        let bNative = scheduler.launch("com.example.ordinary.b")
        await aGate.waitUntilStarted(); await bGate.waitUntilStarted()
        a.lifetime.setStartAllowed(false)
        let stoppingA = Task { @MainActor in await a.lifetime.stop() }
        await aGate.waitUntilCancelled()
        XCTAssertEqual(bNative.completions, [])
        aGate.finishCancellation(); await stoppingA.value
        XCTAssertEqual(aNative.completions, [false])
        bGate.finishSuccess(); await bGate.waitUntilFinished()
        await eventually { bNative.completions == [true] }
    }

    func testSharedRefreshRestoreCancelsAAndPreservesBThenAllowsNewGeneration() async throws {
        let continuedScheduler = P2ContinuedSchedulerSpy()
        let continuedCenter = MiniAppContinuedProcessingCenter(scheduler: continuedScheduler)
        let scheduler = P2BackgroundSchedulerSpy()
        let journal = P2SharedJournal()
        let center = try MiniAppSharedRefreshCenter(
            identifier: "com.example.shared", journal: journal, scheduler: scheduler)
        let aGate = P2BackgroundWorkGate(); let bGate = P2BackgroundWorkGate()
        let a = backgroundFeature("shared-a", continued: continuedCenter, gate: aGate)
        let b = backgroundFeature("shared-b", continued: continuedCenter, gate: bGate)
        let aTasks = center.refreshes(for: MiniAppContext(id: a.id))
        let bTasks = center.refreshes(for: MiniAppContext(id: b.id))
        try aTasks.register(identifier: "refresh") { a.admitShared($0) }
        try bTasks.register(identifier: "refresh") { b.admitShared($0) }
        _ = try aTasks.submit(identifier: "refresh")
        _ = try bTasks.submit(identifier: "refresh")
        let native = scheduler.launch("com.example.shared")
        await aGate.waitUntilStarted(); await bGate.waitUntilStarted()
        let oldGeneration = a.generation
        let restore = a.lifetime.restoreLifecycle
        let stopping = Task { try await restore.stop() }
        await aGate.waitUntilCancelled()
        XCTAssertEqual(native.completions, [])
        XCTAssertTrue(bGate.started)
        aGate.finishCancellation(); try await stopping.value
        try await restore.resume()
        XCTAssertEqual(a.generation, oldGeneration + 1)
        bGate.finishSuccess(); await bGate.waitUntilFinished()
        await eventually { native.completions == [false] }
        XCTAssertEqual(b.lifetime.state, .running)
        XCTAssertTrue(aTasks.pendingRequests.first?.isRecovery == true)
    }

    func testURLSessionColdAdmissionOrderingDisableJoinAndReenable() async throws {
        let continuedScheduler = P2ContinuedSchedulerSpy()
        let continuedCenter = MiniAppContinuedProcessingCenter(scheduler: continuedScheduler)
        let owner = MiniAppID("transfer-a")
        let feature = P2BackgroundFeature(
            id: owner, title: "transfer-a",
            continued: continuedCenter.tasks(for: MiniAppContext(id: owner)), work: { _ in })
        var statuses: [String] = []
        let connection = P2BackgroundURLConnection(owner: owner, feature: feature) {
            statuses.append($0)
        }
        let context = MiniAppContext(id: owner)
        try connection.register(context: context)
        let identifier = try context.backgroundURLSessionIdentifier(profile: "diagnostic")

        feature.lifetime.setStartAllowed(false)
        let rejected = P2CompletionCounter()
        XCTAssertEqual(MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(
            identifier: identifier, completionHandler: rejected.call), .connected)
        await eventually { rejected.count == 1 }
        XCTAssertFalse(connection.hasSession)

        feature.lifetime.setStartAllowed(true)
        try await feature.lifetime.start()
        try connection.bind(runtime: try XCTUnwrap(feature.lifetime.runtime))
        let completion = P2CompletionCounter()
        XCTAssertEqual(MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(
            identifier: identifier, completionHandler: completion.call), .connected)
        await eventually { connection.hasSession }
        XCTAssertEqual(connection.sessionGeneration, 1)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("transfer-a".utf8).write(to: source)
        let task = URLSession.shared.downloadTask(with: URL(string: "https://example.invalid/file")!)
        connection.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: source)
        connection.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        connection.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        await eventually { completion.count == 1 }
        let savedIndex = try XCTUnwrap(statuses.firstIndex { $0.contains("download保存") })
        let finishedIndex = try XCTUnwrap(statuses.firstIndex { $0.contains("host completion解放") })
        XCTAssertLessThan(savedIndex, finishedIndex)

        feature.lifetime.setStartAllowed(false)
        await feature.lifetime.stop() // joins URLSession didBecomeInvalid
        XCTAssertFalse(connection.hasSession)
        feature.lifetime.setStartAllowed(true)
        try await feature.lifetime.start()
        try connection.bind(runtime: try XCTUnwrap(feature.lifetime.runtime))
        let second = P2CompletionCounter()
        XCTAssertEqual(MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(
            identifier: identifier, completionHandler: second.call), .connected)
        await eventually { connection.sessionGeneration == 2 }
        connection.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        await eventually { second.count == 1 }
        await feature.lifetime.stop()
        XCTAssertFalse(connection.hasSession)
    }

    private func feature(_ id: String, center: MiniAppContinuedProcessingCenter,
                         gate: P2WorkGate) -> P2BackgroundFeature {
        let owner = MiniAppID(id)
        return P2BackgroundFeature(id: owner, title: id,
            continued: center.tasks(for: MiniAppContext(id: owner)), work: gate.work)
    }

    private func backgroundFeature(_ id: String, continued: MiniAppContinuedProcessingCenter,
                                   gate: P2BackgroundWorkGate) -> P2BackgroundFeature {
        let owner = MiniAppID(id)
        return P2BackgroundFeature(id: owner, title: id,
            continued: continued.tasks(for: MiniAppContext(id: owner)),
            work: { _ in }, backgroundWork: gate.work)
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class P2WorkGate {
    private var progressCallback: (@MainActor @Sendable (Int64, Int64) -> Void)?
    private var finish: CheckedContinuation<Void, Error>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishedWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var cancelled = false
    private var finished = false

    func work(progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void) async throws {
        progressCallback = progress; started = true
        startedWaiters.forEach { $0.resume() }; startedWaiters.removeAll()
        do { try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { finish = $0 }
        } onCancel: {
            Task { @MainActor in
                self.cancelled = true
                self.cancelledWaiters.forEach { $0.resume() }
                self.cancelledWaiters.removeAll()
            }
        } } catch {
            finished = true; finishedWaiters.forEach { $0.resume() }; finishedWaiters.removeAll()
            throw error
        }
        finished = true; finishedWaiters.forEach { $0.resume() }; finishedWaiters.removeAll()
    }

    func progress(_ completed: Int64, _ total: Int64) { progressCallback?(completed, total) }
    func finishSuccess() { finish?.resume(); finish = nil }
    func finishCancellation() { finish?.resume(throwing: CancellationError()); finish = nil }
    func waitUntilStarted() async {
        if started { return }; await withCheckedContinuation { startedWaiters.append($0) }
    }
    func waitUntilCancelled() async {
        if cancelled { return }; await withCheckedContinuation { cancelledWaiters.append($0) }
    }
    func waitUntilFinished() async {
        if finished { return }; await withCheckedContinuation { finishedWaiters.append($0) }
    }
}

@MainActor
private final class P2WorkSequence {
    private var gates: [P2WorkGate]
    init(_ gates: [P2WorkGate]) { self.gates = gates }
    func work(progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void) async throws {
        guard !gates.isEmpty else { return }
        let gate = gates.removeFirst()
        try await gate.work(progress: progress)
    }
}

@MainActor
private final class P2BackgroundWorkGate {
    private var finish: CheckedContinuation<Void, Error>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var started = false
    private var cancelled = false
    private var finished = false

    func work() async throws {
        started = true; startedWaiters.forEach { $0.resume() }; startedWaiters.removeAll()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { finish = $0 }
            } onCancel: {
                Task { @MainActor in
                    self.cancelled = true
                    self.cancelledWaiters.forEach { $0.resume() }
                    self.cancelledWaiters.removeAll()
                }
            }
        } catch {
            markFinished(); throw error
        }
        markFinished()
    }
    func finishSuccess() { finish?.resume(); finish = nil }
    func finishCancellation() { finish?.resume(throwing: CancellationError()); finish = nil }
    func waitUntilStarted() async {
        if started { return }; await withCheckedContinuation { startedWaiters.append($0) }
    }
    func waitUntilCancelled() async {
        if cancelled { return }; await withCheckedContinuation { cancelledWaiters.append($0) }
    }
    func waitUntilFinished() async {
        if finished { return }; await withCheckedContinuation { finishedWaiters.append($0) }
    }
    private func markFinished() {
        finished = true; finishedWaiters.forEach { $0.resume() }; finishedWaiters.removeAll()
    }
}

@MainActor
private final class P2BackgroundSchedulerSpy: MiniAppBackgroundTaskScheduling {
    var registrations: [String: @MainActor (any MiniAppBackgroundTaskNative) -> Void] = [:]
    var cancellations: [String] = []
    func register(identifier: String, kind: MiniAppBackgroundTaskKind,
                  launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void) -> Bool {
        registrations[identifier] = launch; return true
    }
    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws {}
    func cancel(identifier: String) { cancellations.append(identifier) }
    func launch(_ identifier: String) -> P2BackgroundNativeSpy {
        let native = P2BackgroundNativeSpy(); registrations[identifier]?(native); return native
    }
}

@MainActor
private final class P2BackgroundNativeSpy: MiniAppBackgroundTaskNative {
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    var completions: [Bool] = []
    func setTaskCompleted(success: Bool) { completions.append(success) }
}

@MainActor
private final class P2SharedJournal: MiniAppSharedRefreshJournaling {
    private var records: [MiniAppSharedRefreshRecord] = []
    func load() throws -> [MiniAppSharedRefreshRecord] { records }
    func save(_ records: [MiniAppSharedRefreshRecord]) throws { self.records = records }
}

@MainActor
private final class P2CompletionCounter {
    private(set) var count = 0
    func call() { count += 1 }
}

@MainActor
private final class P2ContinuedSchedulerSpy: MiniAppContinuedProcessingScheduling {
    var registrations: [String: @MainActor (any MiniAppContinuedProcessingNative) -> Void] = [:]
    var submissions: [MiniAppContinuedProcessingRequest] = []
    var cancellations: [String] = []
    func register(identifier: String,
                  launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void) -> Bool {
        registrations[identifier] = launch; return true
    }
    func submit(_ request: MiniAppContinuedProcessingRequest) throws { submissions.append(request) }
    func cancel(identifier: String) { cancellations.append(identifier) }
    func launch(_ identifier: String) -> P2ContinuedNativeSpy {
        let native = P2ContinuedNativeSpy(); registrations[identifier]?(native); return native
    }
}

@MainActor
private final class P2ContinuedNativeSpy: MiniAppContinuedProcessingNative {
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    var completions: [Bool] = []
    func updateProgress(completed: Int64, total: Int64) {}
    func updateTitle(_ title: String, subtitle: String) {}
    func setTaskCompleted(success: Bool) { completions.append(success) }
}
#endif
