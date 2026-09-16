import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppLiveActivityCoordinatorTests: XCTestCase {
    final class JournalBox: @unchecked Sendable {
        let lock = NSLock(); var rows: [MiniAppContinuingRegistration] = []; var failNextSave = false
        func access() -> MiniAppLiveActivityJournalAccess { .init(read: { [self] in lock.withLock { rows } },
            update: { [self] mutation in try lock.withLock {
                if failNextSave { failNextSave = false; throw Failure.injected }
                var copy = rows; try mutation(&copy); rows = copy
            } }) }
    }
    actor FakeDriver: MiniAppLiveActivityNativeDriver {
        typealias StartInput = Int; typealias UpdateInput = Int; typealias EndInput = Int
        var rows: [MiniAppLiveActivityNativeRecord] = []; var requests = 0
        var endedCalls: [String] = []; var failEnd: Set<String> = []
        func request(identity: MiniAppContinuingIdentity, input: Int) async throws -> String {
            requests += 1; let id = "os-\(requests)"
            rows.append(.init(identity: identity, systemID: id, state: .active)); return id
        }
        func records() async -> [MiniAppLiveActivityNativeRecord] { rows }
        func update(systemID: String, input: Int) async {}
        func end(systemID: String, input: Int) async {
            endedCalls.append(systemID)
            guard !failEnd.contains(systemID), let i = rows.firstIndex(where: { $0.systemID == systemID }) else { return }
            rows[i] = .init(identity: rows[i].identity, systemID: systemID, state: .dismissed)
        }
        func awaitEnded(systemID: String) async -> Bool { rows.first(where: { $0.systemID == systemID })?.state == .dismissed }
        func changes() async -> AsyncStream<Void> { AsyncStream { _ in } }
        func append(_ row: MiniAppLiveActivityNativeRecord) { rows.append(row) }
        func setState(_ id: String, _ state: MiniAppLiveActivityNativeRecord.State) {
            guard let i = rows.firstIndex(where: { $0.systemID == id }) else { return }
            rows[i] = .init(identity: rows[i].identity, systemID: id, state: state)
        }
        func setFailEnd(_ ids: Set<String>) { failEnd = ids }
        func counts() -> (Int, [String]) { (requests, endedCalls) }
    }
    enum Failure: Error { case injected }
    let owner = MiniAppID("live-a")
    func identity(owner: MiniAppID? = nil, generation: UUID, registration: UUID = UUID()) throws -> MiniAppContinuingIdentity {
        try .init(owner: owner ?? self.owner, localID: "same-id", generation: generation, registrationID: registration)
    }
    func service(_ journal: JournalBox, _ driver: FakeDriver, generation: UUID) -> MiniAppLiveActivityCoordinator<FakeDriver> {
        .init(owner: owner, gate: .init(), journal: journal.access(), native: driver) { identity in
            guard identity.generation == generation else { throw MiniAppLiveActivityError.staleIdentity }
        }
    }

    func testNewRegistrationIDDoesNotDuplicateSameBusinessActivity() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID(), sut = service(journal, driver, generation: generation)
        let first = try await sut.start(identity: identity(generation: generation), input: 1)
        let second = try await sut.start(identity: identity(generation: generation), input: 2)
        XCTAssertEqual(first, second)
        let counts = await driver.counts(); XCTAssertEqual(counts.0, 1)
    }

    func testActivationSaveFailureIsRepairedFromExactNativeIdentity() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let access = journal.access()
        let wrapped = MiniAppLiveActivityJournalAccess(read: access.read, update: { mutation in
            let wasEmpty = try access.read().isEmpty
            try access.update(mutation)
            if wasEmpty { journal.failNextSave = true }
        })
        let sut = MiniAppLiveActivityCoordinator(owner: owner, gate: .init(), journal: wrapped, native: driver,
            admission: { identity in guard identity.generation == generation else { throw MiniAppLiveActivityError.staleIdentity } })
        let key = try identity(generation: generation)
        await XCTAssertThrowsErrorAsync { try await sut.start(identity: key, input: 1) }
        XCTAssertNil(journal.rows.first?.systemID)
        _ = try await sut.reconcile()
        XCTAssertEqual(journal.rows.first?.systemID, "os-1")
        XCTAssertEqual(journal.rows.first?.phase, .active)
    }

    func testEndedRegistrationIsNotReturnedAsSuccessfulStart() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID(), sut = service(journal, driver, generation: generation)
        let first = try await sut.start(identity: identity(generation: generation), input: 1)
        await driver.setState(first.systemID, .ended)
        let second = try await sut.start(identity: identity(generation: generation), input: 2)
        XCTAssertNotEqual(first.systemID, second.systemID)
    }

    func testInvalidInputsNeverRunBusinessMutation() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID(), sut = service(journal, driver, generation: generation)
        let current = try await sut.start(identity: identity(generation: generation), input: 1)
        let mutationCount = LockedInt()
        let candidates = [
            MiniAppLiveActivityDescriptor(identity: try identity(owner: MiniAppID("live-b"), generation: generation), systemID: current.systemID),
            MiniAppLiveActivityDescriptor(identity: try .init(owner: owner, localID: "wrong", generation: generation), systemID: current.systemID),
            MiniAppLiveActivityDescriptor(identity: try identity(generation: UUID()), systemID: current.systemID),
            MiniAppLiveActivityDescriptor(identity: try identity(generation: generation), systemID: current.systemID),
            MiniAppLiveActivityDescriptor(identity: current.identity, systemID: "wrong-system")]
        for candidate in candidates {
            await XCTAssertThrowsErrorAsync { try await sut.update(candidate) { mutationCount.increment(); return (1, 1) } }
        }
        XCTAssertEqual(mutationCount.value, 0)
    }

    func testReconcileKeepsEndingAndReportsMismatchUnknownAndDuplicates() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID(), sut = service(journal, driver, generation: generation)
        let descriptor = try await sut.start(identity: identity(generation: generation), input: 1)
        journal.rows[0].phase = .ending
        journal.rows[0].systemID = "mismatched-saved-id"
        await driver.append(.init(identity: descriptor.identity, systemID: "duplicate", state: .active))
        let unknown = try identity(generation: generation, registration: UUID())
        await driver.append(.init(identity: unknown, systemID: "unknown", state: .active))
        let report = try await sut.reconcile()
        XCTAssertEqual(journal.rows.first?.phase, .ending)
        XCTAssertTrue(report.duplicateSystemIDs.contains("duplicate"))
        XCTAssertTrue(report.mismatchedSystemIDs.contains(descriptor.systemID))
        XCTAssertTrue(report.unknownSystemIDs.contains("unknown"))
    }

    func testEndOwnedAttemptsEveryActivityAndRetainsFailedRecord() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID(), sut = service(journal, driver, generation: generation)
        let first = try await sut.start(identity: identity(generation: generation), input: 1)
        let secondIdentity = try MiniAppContinuingIdentity(owner: owner, localID: "second", generation: generation)
        let secondID = try await driver.request(identity: secondIdentity, input: 2)
        journal.rows.append(.init(identity: secondIdentity, systemID: secondID, phase: .active))
        await driver.setFailEnd([first.systemID])
        await XCTAssertThrowsErrorAsync { try await sut.endOwned { _ in 0 } }
        let counts = await driver.counts()
        let calls = counts.1
        XCTAssertEqual(Set(calls), Set([first.systemID, secondID]))
        XCTAssertTrue(journal.rows.contains { $0.systemID == first.systemID })
        XCTAssertFalse(journal.rows.contains { $0.systemID == secondID })
    }

    func testStartCannotReopenAnEndingActivityOrRepairAMismatchedSystemID() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let sut = service(journal, driver, generation: generation)
        let first = try await sut.start(identity: identity(generation: generation), input: 1)
        journal.rows[0].phase = .ending
        await XCTAssertThrowsErrorAsync { try await sut.start(identity: self.identity(generation: generation), input: 2) }
        XCTAssertEqual(journal.rows[0].phase, .ending)
        journal.rows[0].phase = .active
        journal.rows[0].systemID = "mismatch"
        await XCTAssertThrowsErrorAsync { try await sut.start(identity: self.identity(generation: generation), input: 3) }
        XCTAssertEqual(journal.rows[0].systemID, "mismatch")
        let counts = await driver.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(first.systemID, "os-1")
    }

    func testColdHandleRecoveryDoesNotRequestAnotherActivity() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let first = service(journal, driver, generation: generation)
        let handle = try await first.start(identity: identity(generation: generation), input: 10)
        let reconstructed = service(journal, driver, generation: generation)
        _ = try await reconstructed.reconcile()
        let recovered = try await reconstructed.current(localID: "same-id", generation: generation)
        XCTAssertEqual(recovered, handle)
        let counts = await driver.counts()
        XCTAssertEqual(counts.0, 1)
        await driver.setState(handle.systemID, .ended)
        let ended = try await reconstructed.current(localID: "same-id", generation: generation)
        XCTAssertNil(ended)
    }

    func testForeignJournalFailsClosedWithoutChangingEitherOwner() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let foreign = try identity(owner: MiniAppID("live-b"), generation: generation)
        let systemID = try await driver.request(identity: foreign, input: 5)
        journal.rows = [.init(identity: foreign, systemID: systemID, phase: .active)]
        let before = journal.rows
        let sut = service(journal, driver, generation: generation)
        await XCTAssertThrowsErrorAsync { try await sut.reconcile() }
        await XCTAssertThrowsErrorAsync { try await sut.endOwned { _ in 0 } }
        XCTAssertEqual(journal.rows, before)
        let counts = await driver.counts()
        XCTAssertTrue(counts.1.isEmpty)
    }

    func testObservationCreationIsDeduplicatedAndCloseDrainsIt() async throws {
        let probe = ObservedDriver()
        let journal = JournalBox()
        let coordinator = MiniAppLiveActivityCoordinator(owner: owner, gate: .init(), journal: journal.access(),
            native: probe, admission: { _ in })
        try await coordinator.observe()
        await probe.waitForCreation()
        try await coordinator.observe()
        try await coordinator.observe()
        await coordinator.close()
        let count = await probe.streamCount
        XCTAssertEqual(count, 1)
        await XCTAssertThrowsErrorAsync { try await coordinator.observe() }
    }
}

private actor ObservedDriver: MiniAppLiveActivityNativeDriver {
    typealias StartInput = Int
    typealias UpdateInput = Int
    typealias EndInput = Int
    var streamCount = 0
    var waiting: CheckedContinuation<Void, Never>?
    func request(identity: MiniAppContinuingIdentity, input: Int) async throws -> String { "unused" }
    func records() async -> [MiniAppLiveActivityNativeRecord] { [] }
    func update(systemID: String, input: Int) async {}
    func end(systemID: String, input: Int) async {}
    func awaitEnded(systemID: String) async -> Bool { true }
    func changes() async -> AsyncStream<Void> {
        streamCount += 1
        waiting?.resume()
        waiting = nil
        return AsyncStream { _ in }
    }
    func waitForCreation() async {
        if streamCount == 0 { await withCheckedContinuation { waiting = $0 } }
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock(); private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}
private func XCTAssertThrowsErrorAsync<T>(_ expression: () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch {}
}
