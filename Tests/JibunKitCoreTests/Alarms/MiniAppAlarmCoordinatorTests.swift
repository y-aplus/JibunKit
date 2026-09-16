import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppAlarmCoordinatorTests: XCTestCase {
    func testScheduleFailureRetainsStartingJournal() async throws {
        let native = FakeAlarmNative()
        await native.failNextSchedule()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)

        do {
            _ = try await service.schedule(localID: "same-id", generation: UUID()) { _, _ in "A" }
            XCTFail("schedule should fail")
        } catch FakeFailure.injected {}

        let records = try store.read()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].phase, .starting)
        XCTAssertNotNil(records[0].systemID.flatMap(UUID.init(uuidString:)))
    }

    func testPendingRetryUsesPersistedIdentityAndSystemID() async throws {
        let native = FakeAlarmNative()
        await native.failNextSchedule()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let generation = UUID()
        do { _ = try await service.schedule(localID: "same-id", generation: generation) { _, _ in "first" } }
        catch FakeFailure.injected {}
        let pending = try XCTUnwrap(store.read().first)
        let originalID = try XCTUnwrap(pending.systemID.flatMap(UUID.init(uuidString:)))

        try await service.retryPending(pending.identity) { _, _ in "retry" }

        XCTAssertEqual(try store.read().first?.phase, .active)
        XCTAssertEqual(try store.read().first?.systemID, originalID.uuidString)
        let nativeContainsOriginal = await native.contains(originalID)
        XCTAssertTrue(nativeContainsOriginal)
    }

    func testPartialReplacementKeepsBothRegistrationsAndOtherOwner() async throws {
        let native = FakeAlarmNative()
        let storeA = MemoryAlarmStore()
        let storeB = MemoryAlarmStore()
        let a = coordinator(owner: "alarm-a", native: native, store: storeA)
        let b = coordinator(owner: "alarm-b", native: native, store: storeB)
        let generation = UUID()
        let oldA = try await a.schedule(localID: "same-id", generation: generation) { _, _ in "A-old" }
        let identityB = try await b.schedule(localID: "same-id", generation: generation) { _, _ in "B" }
        let bBefore = try storeB.read()
        await native.failCancel(for: try systemID(storeA, oldA))

        do {
            _ = try await a.replace(oldA) { _, _ in "A-new" }
            XCTFail("replacement should report its partial result")
        } catch MiniAppAlarmError.partialReplacement(_, _, _, _) {}

        XCTAssertEqual(try storeA.read().count, 2)
        XCTAssertEqual(try storeB.read(), bBefore)
        let bStillNative = await native.contains(try systemID(storeB, identityB))
        XCTAssertTrue(bStillNative)
    }

    func testRejectsOldGenerationAndRegistrationID() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let current = try await service.schedule(localID: "same-id", generation: UUID()) { _, _ in "A" }
        let staleGeneration = try MiniAppContinuingIdentity(owner: MiniAppID("alarm-a"), localID: "same-id",
                                                            generation: UUID())
        let staleRegistration = try MiniAppContinuingIdentity(owner: MiniAppID("alarm-a"), localID: "same-id",
                                                              generation: current.generation)

        await XCTAssertThrowsErrorAsync(try await service.perform(.cancel, identity: staleGeneration)) {
            XCTAssertEqual($0 as? MiniAppAlarmError, .staleGeneration)
        }
        await XCTAssertThrowsErrorAsync(try await service.perform(.cancel, identity: staleRegistration)) {
            XCTAssertEqual($0 as? MiniAppAlarmError, .staleRegistration)
        }
        XCTAssertEqual(try store.read().count, 1)
    }

    func testColdReconcileRecoversStartingCompletesEndingAndReportsUnknown() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let owner = MiniAppID("alarm-a")
        let starting = try MiniAppContinuingIdentity(owner: owner, localID: "start", generation: UUID())
        let ending = try MiniAppContinuingIdentity(owner: owner, localID: "end", generation: UUID())
        let startID = UUID(), endID = UUID(), unknown = UUID()
        try store.write([
            .init(identity: starting, systemID: startID.uuidString, phase: .starting),
            .init(identity: ending, systemID: endID.uuidString, phase: .ending),
        ])
        await native.seed(id: startID, state: .scheduled)
        await native.seed(id: unknown, state: .scheduled)
        let service = coordinator(owner: "alarm-a", native: native, store: store)

        let result = try await service.reconcile()

        XCTAssertEqual(result.recoveredStarting, [starting])
        XCTAssertEqual(result.completedEnding, [ending])
        XCTAssertEqual(result.unknownSystemIDs, [unknown])
        XCTAssertEqual(try store.read().map(\.phase), [.active])
        let unknownRemains = await native.contains(unknown)
        XCTAssertTrue(unknownRemains, "unknown OS alarms belong to no inferred owner")
    }

    func testCancelMustConvergeAndEndOwnedDoesNotTouchB() async throws {
        let native = FakeAlarmNative()
        let storeA = MemoryAlarmStore(), storeB = MemoryAlarmStore()
        let a = coordinator(owner: "alarm-a", native: native, store: storeA, attempts: 2)
        let b = coordinator(owner: "alarm-b", native: native, store: storeB, attempts: 2)
        let generation = UUID()
        let identityA = try await a.schedule(localID: "same-id", generation: generation) { _, _ in "A" }
        let identityB = try await b.schedule(localID: "same-id", generation: generation) { _, _ in "B" }
        await native.ignoreCancel(for: try systemID(storeA, identityA))

        await XCTAssertThrowsErrorAsync(try await a.endOwned()) {
            guard let error = $0 as? MiniAppAlarmError,
                  case .nativeDidNotConverge(.cancel, _) = error else {
                return XCTFail("unexpected error: \($0)")
            }
        }
        XCTAssertEqual(try storeA.read().first?.phase, .ending)
        let bStillNative = await native.contains(try systemID(storeB, identityB))
        XCTAssertTrue(bStillNative)
        XCTAssertEqual(try storeB.read().count, 1)
    }

    func testSystemStopIntentValidatesThenDoesNotDuplicateNativeStop() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let identity = try await service.schedule(localID: "same-id", generation: UUID()) { _, _ in "A" }
        let id = try systemID(store, identity)
        let callback = CallbackCounter()

        try await service.handleSystemIntent(identity: identity, systemID: id) { await callback.hit() }

        let callbackValue = await callback.value
        let nativeActions = await native.actions
        XCTAssertEqual(callbackValue, 1)
        XCTAssertTrue(nativeActions.isEmpty)
    }

    func testRepeatedReconcileKeepsStoppedCallbackTombstoneUntilIntentConsumesIt() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let generation = UUID()
        let first = try await service.schedule(localID: "same-id", generation: generation) { _, _ in "first" }
        let firstID = try systemID(store, first)
        await native.remove(firstID)

        _ = try await service.reconcile()
        _ = try await service.reconcile()
        XCTAssertEqual(try store.read().first?.phase, .active)
        let callback = CallbackCounter()
        try await service.handleSystemIntent(identity: first, systemID: firstID) { await callback.hit() }
        let callbackValue = await callback.value
        XCTAssertEqual(callbackValue, 1)
        XCTAssertTrue(try store.read().isEmpty)

    }

    func testExplicitRescheduleSupersedesTombstoneAndRejectsOldCallback() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let generation = UUID()
        let first = try await service.schedule(localID: "same-id", generation: generation) { _, _ in "first" }
        let firstID = try systemID(store, first)
        await native.remove(firstID)
        _ = try await service.reconcile()

        let second = try await service.schedule(localID: "same-id", generation: generation) { _, _ in "second" }
        XCTAssertNotEqual(first.registrationID, second.registrationID)
        let callback = CallbackCounter()
        await XCTAssertThrowsErrorAsync(try await service.handleSystemIntent(identity: first, systemID: firstID) {
            await callback.hit()
        })
        let value = await callback.value
        XCTAssertEqual(value, 0)
    }

    func testEndOwnedTreatsAlreadyAbsentAsCompletedAndContinuesAfterBadRow() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let owner = MiniAppID("alarm-a")
        let bad = try MiniAppContinuingIdentity(owner: owner, localID: "bad", generation: UUID())
        let absent = try MiniAppContinuingIdentity(owner: owner, localID: "absent", generation: UUID())
        try store.write([
            .init(identity: bad, systemID: "not-a-uuid", phase: .active),
            .init(identity: absent, systemID: UUID().uuidString, phase: .active),
        ])
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        await XCTAssertThrowsErrorAsync(try await service.endOwned())
        XCTAssertEqual(try store.read().map(\.identity), [bad], "later absent row must still be completed")
    }

    func testReplacementReportsJournalFailuresAtBothCommitStages() async throws {
        for successfulWritesBeforeFailure in [1, 2] {
            let native = FakeAlarmNative()
            let store = MemoryAlarmStore()
            let service = coordinator(owner: "alarm-a", native: native, store: store)
            let old = try await service.schedule(localID: "same-id", generation: UUID()) { _, _ in "old" }
            store.failWrite(afterSuccessfulWrites: successfulWritesBeforeFailure)
            do {
                _ = try await service.replace(old) { _, _ in "new" }
                XCTFail("journal failure should be a partial replacement")
            } catch let MiniAppAlarmError.partialReplacement(newID, oldID, stage, reason) {
                XCTAssertNotEqual(newID, oldID)
                XCTAssertFalse(stage.isEmpty)
                XCTAssertTrue(reason.contains("injected"))
            }
            XCTAssertEqual(try store.read().count, 2, "both recovery IDs must remain")
            let recovery = try await service.reconcile()
            XCTAssertEqual(recovery.active.count, 1)
            XCTAssertEqual(recovery.duplicates.count, 1)
            XCTAssertEqual(try store.read().filter { $0.phase == .ending }.count, 1)
        }
    }

    func testStartingAndReplacementEndingRejectBusinessCallback() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let owner = MiniAppID("alarm-a"), generation = UUID()
        let ending = try MiniAppContinuingIdentity(owner: owner, localID: "same-id", generation: generation)
        let active = try MiniAppContinuingIdentity(owner: owner, localID: "same-id", generation: generation)
        let endingID = UUID(), activeID = UUID()
        try store.write([
            .init(identity: ending, systemID: endingID.uuidString, phase: .ending),
            .init(identity: active, systemID: activeID.uuidString, phase: .active),
        ])
        await native.seed(id: activeID, state: .scheduled)
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let callback = CallbackCounter()
        await XCTAssertThrowsErrorAsync(try await service.handleSystemIntent(identity: ending, systemID: endingID) {
            await callback.hit()
        })
        let callbackValue = await callback.value
        XCTAssertEqual(callbackValue, 0)
        await XCTAssertThrowsErrorAsync(try await service.replace(ending) { _, _ in "must-not-schedule" }) {
            XCTAssertEqual($0 as? MiniAppAlarmError, .staleRegistration)
        }

        let starting = try MiniAppContinuingIdentity(owner: owner, localID: "pending", generation: generation)
        let startingID = UUID()
        try store.write(try store.read() + [
            .init(identity: starting, systemID: startingID.uuidString, phase: .starting),
        ])
        await XCTAssertThrowsErrorAsync(try await service.handleSystemIntent(identity: starting, systemID: startingID) {
            await callback.hit()
        })
        let afterStarting = await callback.value
        XCTAssertEqual(afterStarting, 0)
    }

    func testEndingWithoutSiblingStillRejectsCallback() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let owner = MiniAppID("alarm-a")
        let identity = try MiniAppContinuingIdentity(owner: owner, localID: "same-id", generation: UUID())
        let id = UUID()
        try store.write([.init(identity: identity, systemID: id.uuidString, phase: .ending)])
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        let callback = CallbackCounter()
        await XCTAssertThrowsErrorAsync(try await service.handleSystemIntent(identity: identity, systemID: id) {
            await callback.hit()
        })
        let value = await callback.value
        XCTAssertEqual(value, 0)
    }

    func testMiswiredForeignOwnerStoreFailsBeforeNativeOrJournalMutation() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let ownerB = MiniAppID("alarm-b")
        let identityB = try MiniAppContinuingIdentity(owner: ownerB, localID: "same-id", generation: UUID())
        let idB = UUID()
        try store.write([.init(identity: identityB, systemID: idB.uuidString, phase: .active)])
        await native.seed(id: idB, state: .scheduled)
        let before = try store.read()
        let serviceA = coordinator(owner: "alarm-a", native: native, store: store)

        await XCTAssertThrowsErrorAsync(try await serviceA.endOwned()) {
            XCTAssertEqual($0 as? MiniAppAlarmError, .wrongOwner)
        }

        XCTAssertEqual(try store.read(), before)
        let bStillNative = await native.contains(idB)
        let actions = await native.actions
        XCTAssertTrue(bStillNative)
        XCTAssertTrue(actions.isEmpty)
    }

    func testReconcileIsPassiveAndObserveCreatesOneProducerUntilReopened() async throws {
        let native = CountingUpdateNative()
        let store = MemoryAlarmStore()
        let service = MiniAppAlarmCoordinator(owner: MiniAppID("alarm-a"), native: native, store: store,
            confirmationAttempts: 1, confirmationDelayNanoseconds: 0) { _, _ in }

        _ = try await service.reconcile()
        _ = try await service.reconcile()
        XCTAssertEqual(native.starts, 0)
        try await service.observe()
        try await service.observe()
        for _ in 0..<10 where native.starts == 0 { await Task.yield() }
        XCTAssertEqual(native.starts, 1)
        await service.close()
        try await service.open()
        for _ in 0..<10 where native.starts == 1 { await Task.yield() }
        XCTAssertEqual(native.starts, 2)
        await service.close()
    }

    func testCurrentRejectsMultipleMatchesAndUnknownDoesNotPromoteStarting() async throws {
        let native = FakeAlarmNative()
        let store = MemoryAlarmStore()
        let owner = MiniAppID("alarm-a"), generation = UUID()
        let first = try MiniAppContinuingIdentity(owner: owner, localID: "same-id", generation: generation)
        let second = try MiniAppContinuingIdentity(owner: owner, localID: "same-id", generation: generation)
        let firstID = UUID(), secondID = UUID()
        try store.write([
            .init(identity: first, systemID: firstID.uuidString, phase: .active),
            .init(identity: second, systemID: secondID.uuidString, phase: .active),
        ])
        await native.seed(id: firstID, state: .scheduled)
        await native.seed(id: secondID, state: .scheduled)
        let service = coordinator(owner: "alarm-a", native: native, store: store)
        await XCTAssertThrowsErrorAsync(try await service.current(localID: "same-id", generation: generation)) {
            XCTAssertEqual($0 as? MiniAppAlarmError, .staleRegistration)
        }

        let pending = try MiniAppContinuingIdentity(owner: owner, localID: "pending", generation: generation)
        let pendingID = UUID()
        try store.write([.init(identity: pending, systemID: pendingID.uuidString, phase: .starting)])
        await native.remove(firstID)
        await native.remove(secondID)
        await native.seed(id: pendingID, state: .unknown)
        let result = try await service.reconcile()
        XCTAssertFalse(result.recoveredStarting.contains(pending))
        XCTAssertEqual(try store.read().first?.phase, .starting)
    }

    private func coordinator(owner: String, native: FakeAlarmNative, store: MemoryAlarmStore,
                             attempts: Int = 1) -> MiniAppAlarmCoordinator<FakeAlarmNative> {
        MiniAppAlarmCoordinator(owner: MiniAppID(owner), native: native, store: store,
                                confirmationAttempts: attempts, confirmationDelayNanoseconds: 0) { _, _ in }
    }

    private func systemID(_ store: MemoryAlarmStore, _ identity: MiniAppContinuingIdentity) throws -> UUID {
        let value = try XCTUnwrap(store.read().first { $0.identity == identity }?.systemID)
        return try XCTUnwrap(UUID(uuidString: value))
    }
}

private enum FakeFailure: Error { case injected }

private actor FakeAlarmNative: MiniAppAlarmNative {
    typealias Configuration = String
    private var values: [UUID: MiniAppAlarmState] = [:]
    private var scheduleFailure = false
    private var cancelFailures: Set<UUID> = []
    private var ignoredCancels: Set<UUID> = []
    private(set) var actions: [(MiniAppAlarmAction, UUID)] = []

    func failNextSchedule() { scheduleFailure = true }
    func failCancel(for id: UUID) { cancelFailures.insert(id) }
    func ignoreCancel(for id: UUID) { ignoredCancels.insert(id) }
    func seed(id: UUID, state: MiniAppAlarmState) { values[id] = state }
    func remove(_ id: UUID) { values[id] = nil }
    func contains(_ id: UUID) -> Bool { values[id] != nil }

    func schedule(id: UUID, configuration: String) throws {
        if scheduleFailure { scheduleFailure = false; throw FakeFailure.injected }
        values[id] = .scheduled
    }

    func perform(_ action: MiniAppAlarmAction, id: UUID) throws {
        actions.append((action, id))
        if action == .cancel && cancelFailures.remove(id) != nil { throw FakeFailure.injected }
        if action == .cancel && ignoredCancels.contains(id) { return }
        switch action {
        case .cancel, .stop: values[id] = nil
        case .pause: values[id] = .paused
        case .resume, .countdown: values[id] = .countdown
        }
    }

    func snapshots() -> [MiniAppAlarmSnapshot] {
        values.map { .init(id: $0.key, state: $0.value) }
    }
}

private final class CountingUpdateNative: MiniAppAlarmNative, @unchecked Sendable {
    typealias Configuration = String
    private let lock = NSLock()
    private var startCount = 0
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    var starts: Int { lock.withLock { startCount } }

    func schedule(id: UUID, configuration: String) async throws {}
    func perform(_ action: MiniAppAlarmAction, id: UUID) async throws {}
    func snapshots() async throws -> [MiniAppAlarmSnapshot] { [] }
    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                startCount += 1
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.continuations[id] = nil }
            }
        }
    }
}

private final class MemoryAlarmStore: MiniAppAlarmRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [MiniAppContinuingRegistration] = []
    private var successfulWritesBeforeFailure: Int?
    func read() throws -> [MiniAppContinuingRegistration] { lock.withLock { records } }
    func write(_ registrations: [MiniAppContinuingRegistration]) throws {
        try lock.withLock {
            if let remaining = successfulWritesBeforeFailure {
                if remaining == 0 { successfulWritesBeforeFailure = nil; throw FakeFailure.injected }
                successfulWritesBeforeFailure = remaining - 1
            }
            records = registrations
        }
    }
    func failWrite(afterSuccessfulWrites count: Int) { lock.withLock { successfulWritesBeforeFailure = count } }
}

private actor CallbackCounter {
    private(set) var value = 0
    func hit() { value += 1 }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await expression(); XCTFail("expected error", file: file, line: line) }
    catch { errorHandler(error) }
}
