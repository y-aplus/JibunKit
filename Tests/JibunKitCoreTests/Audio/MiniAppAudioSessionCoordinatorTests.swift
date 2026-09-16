import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppAudioSessionCoordinatorTests: XCTestCase {
    private let playback = MiniAppAudioProfile(category: .playback, mode: .spokenAudio)
    private let duplex = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
    private let measurement = MiniAppAudioProfile(category: .playAndRecord, mode: .measurement)

    func testCompatibleOwnersShareExplicitProfileAndLastReleaseDeactivates() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let a = try acquired(await coordinator.acquire(
            owner: MiniAppID("a"), request: request([playback, duplex]), stop: { driver.events.append("stop-a") }, receive: { _ in }
        ))
        let b = try acquired(await coordinator.acquire(
            owner: MiniAppID("b"), request: request([duplex]), stop: { driver.events.append("stop-b") }, receive: { _ in }
        ))

        XCTAssertEqual(coordinator.activeProfile, duplex)
        try await coordinator.release(a)
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("b")])
        XCTAssertFalse(driver.events.contains("active-false"))
        try await coordinator.release(b)
        XCTAssertEqual(Array(driver.events.suffix(2)), ["stop-b", "active-false"])
    }

    func testConflictRequiresExplicitReplacementAndWaitsForStop() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let gate = AsyncGate()
        _ = try acquired(await coordinator.acquire(
            owner: MiniAppID("player"), request: request([playback]),
            stop: { driver.events.append("stop-enter"); await gate.wait(); driver.events.append("stop-finished") }, receive: { _ in }
        ))
        let admission = try await coordinator.acquire(
            owner: MiniAppID("recorder"), request: request([measurement]), stop: {}, receive: { _ in }
        )
        let conflict = try conflict(admission)
        let resolving = Task { @MainActor in
            try await coordinator.resolve(conflict, as: .replaceOwners([MiniAppID("player")]))
        }
        await gate.waitUntilEntered()
        XCTAssertFalse(driver.events.contains("apply-playAndRecord-measurement"))
        gate.open()
        let recorder = try await resolving.value
        XCTAssertEqual(recorder.owner, MiniAppID("recorder"))
        XCTAssertEqual(Array(driver.events.prefix(2)), ["apply-playback-spokenAudio", "active-true"])
        XCTAssertTrue(driver.events.firstIndex(of: "stop-finished")! < driver.events.firstIndex(of: "apply-playAndRecord-measurement")!)
    }

    func testPartialStopReportsRealityAndKeepsUnstoppedOwner() async throws {
        struct StopFailure: Error {}
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        _ = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {}, receive: { _ in }))
        _ = try acquired(await coordinator.acquire(owner: MiniAppID("b"), request: request([playback]), stop: { throw StopFailure() }, receive: { _ in }))
        let c = try conflict(await coordinator.acquire(owner: MiniAppID("c"), request: request([measurement]), stop: {}, receive: { _ in }))
        do {
            _ = try await coordinator.resolve(c, as: .replaceOwners([MiniAppID("a"), MiniAppID("b")]))
            XCTFail("Expected partial stop")
        } catch MiniAppAudioSessionCoordinator.Failure.partialStop(let partial) {
            XCTAssertEqual(partial.stoppedOwners, [MiniAppID("a")])
            XCTAssertEqual(partial.remainingOwners, [MiniAppID("b")])
            XCTAssertEqual(coordinator.activeOwners, [MiniAppID("b")])
        }
    }

    func testOldConflictCannotStopNewGeneration() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let first = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {}, receive: { _ in }))
        let stale = try conflict(await coordinator.acquire(owner: MiniAppID("b"), request: request([measurement]), stop: {}, receive: { _ in }))
        try await coordinator.release(first)
        let second = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {}, receive: { _ in }))
        XCTAssertGreaterThan(second.generation, first.generation)
        do {
            _ = try await coordinator.resolve(stale, as: .replaceOwners([MiniAppID("a")]))
            XCTFail("Expected stale conflict")
        } catch MiniAppAudioSessionCoordinator.Failure.staleConflict {}
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("a")])
    }

    func testDriverFailureAfterStopReportsPartialStateAndDoesNotAdmitRequester() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        _ = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {}, receive: { _ in }))
        let conflict = try conflict(await coordinator.acquire(owner: MiniAppID("b"), request: request([measurement]), stop: {}, receive: { _ in }))
        driver.failingProfile = measurement
        do {
            _ = try await coordinator.resolve(conflict, as: .replaceOwners([MiniAppID("a")]))
            XCTFail("Expected partial stop")
        } catch MiniAppAudioSessionCoordinator.Failure.partialStop(let partial) {
            XCTAssertEqual(partial.stoppedOwners, [MiniAppID("a")])
            XCTAssertTrue(partial.remainingOwners.isEmpty)
            XCTAssertTrue(coordinator.activeOwners.isEmpty)
        }
    }

    func testUserStopAndRouteStopPreventInterruptionResume() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let events = EventBox()
        let lease = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {}, receive: { events.values.append($0) }))
        try coordinator.updateIntent(.active, for: lease)
        coordinator.receiveInterruptionBegan()
        try coordinator.updateIntent(.stoppedByUser, for: lease)
        coordinator.receiveInterruptionEnded(shouldResume: true)
        XCTAssertEqual(Array(events.values.suffix(2)), [.interruptionBegan, .interruptionEnded(resumeCandidate: false)])

        try coordinator.updateIntent(.active, for: lease)
        coordinator.receiveInterruptionBegan()
        try coordinator.updateIntent(.stoppedForRouteChange, for: lease)
        coordinator.receiveInterruptionEnded(shouldResume: true)
        XCTAssertEqual(events.values.last, .interruptionEnded(resumeCandidate: false))
    }

    func testStopCannotRecursivelyReleaseSameLease() async throws {
        let driver = FakeAudioSessionDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let state = ReentryBox()
        state.lease = try acquired(await coordinator.acquire(owner: MiniAppID("a"), request: request([playback]), stop: {
            do { try await coordinator.release(state.lease!) }
            catch let failure as MiniAppAudioSessionCoordinator.Failure { state.failure = failure }
        }, receive: { _ in }))
        try await coordinator.release(state.lease!)
        XCTAssertEqual(state.failure, .stopReentry)
    }

    private func request(_ profiles: [MiniAppAudioProfile]) -> MiniAppAudioRequest {
        MiniAppAudioRequest(acceptableProfiles: profiles, purpose: "test")
    }

    private func acquired(_ admission: MiniAppAudioSessionCoordinator.Admission) throws -> MiniAppAudioSessionCoordinator.Lease {
        guard case .acquired(let lease) = admission else { throw TestFailure.wrongAdmission }
        return lease
    }

    private func conflict(_ admission: MiniAppAudioSessionCoordinator.Admission) throws -> MiniAppAudioSessionCoordinator.Conflict {
        guard case .conflict(let conflict) = admission else { throw TestFailure.wrongAdmission }
        return conflict
    }

    private enum TestFailure: Error { case wrongAdmission }
}

@MainActor
private final class FakeAudioSessionDriver: MiniAppAudioSessionDriver {
    var events: [String] = []
    var failingProfile: MiniAppAudioProfile?
    func apply(_ profile: MiniAppAudioProfile) throws {
        if profile == failingProfile { throw FakeFailure.apply }
        events.append("apply-\(profile.category.rawValue)-\(profile.mode.rawValue)")
    }
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        events.append("active-\(active)")
    }
    private enum FakeFailure: Error { case apply }
}

@MainActor
private final class AsyncGate {
    private var entered = false
    private var openState = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        if openState { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }
    func open() {
        openState = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@MainActor private final class EventBox { var values: [MiniAppAudioEvent] = [] }
@MainActor private final class ReentryBox {
    var lease: MiniAppAudioSessionCoordinator.Lease?
    var failure: MiniAppAudioSessionCoordinator.Failure?
}
