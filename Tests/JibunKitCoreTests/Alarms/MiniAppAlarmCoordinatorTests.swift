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
        } catch MiniAppAlarmError.partialReplacement {}

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

private final class MemoryAlarmStore: MiniAppAlarmRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [MiniAppContinuingRegistration] = []
    func read() throws -> [MiniAppContinuingRegistration] { lock.withLock { records } }
    func write(_ registrations: [MiniAppContinuingRegistration]) throws { lock.withLock { records = registrations } }
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
