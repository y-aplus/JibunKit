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
