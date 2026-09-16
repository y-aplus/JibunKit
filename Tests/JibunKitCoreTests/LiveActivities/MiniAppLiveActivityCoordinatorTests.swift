import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppLiveActivityCoordinatorTests: XCTestCase {
    struct Content: Equatable, Sendable { var value: Int }

    final class JournalBox: @unchecked Sendable {
        let lock = NSLock()
        var rows: [MiniAppContinuingRegistration] = []
        var failNextSave = false
        func access() -> MiniAppLiveActivityJournalAccess {
            .init(read: { [self] in lock.withLock { rows } }, update: { [self] mutation in
                try lock.withLock {
                    if failNextSave { failNextSave = false; throw Failure.injected }
                    var copy = rows
                    try mutation(&copy)
                    rows = copy
                }
            })
        }
    }

    actor FakeDriver: MiniAppLiveActivityNativeDriver {
        var rows: [MiniAppLiveActivityNativeRecord] = []
        var requests = 0
        var resolveUpdate = true
        var resolveImmediateEnd = true

        func request(identity: MiniAppContinuingIdentity, content: Content) async throws -> String {
            requests += 1
            let id = "os-\(requests)"
            rows.append(.init(identity: identity, systemID: id, state: .active))
            return id
        }
        func records() async -> [MiniAppLiveActivityNativeRecord] { rows }
        func update(systemID: String, content: Content) async {}
        func end(systemID: String, finalContent: Content, immediately: Bool) async {
            guard resolveImmediateEnd || !immediately,
                  let index = rows.firstIndex(where: { $0.systemID == systemID }) else { return }
            rows[index] = .init(identity: rows[index].identity, systemID: systemID,
                                state: immediately ? .dismissed : .ended)
        }
        func awaitState(systemID: String, accepted: Set<MiniAppLiveActivityNativeRecord.State>) async -> Bool {
            if accepted == [.active, .stale], !resolveUpdate { return false }
            return rows.first(where: { $0.systemID == systemID }).map { accepted.contains($0.state) }
                ?? accepted.contains(.dismissed)
        }
        func requestCount() -> Int { requests }
        func setResolveUpdate(_ value: Bool) { resolveUpdate = value }
        func setResolveEnd(_ value: Bool) { resolveImmediateEnd = value }
    }

    enum Failure: Error { case injected }
    let owner = MiniAppID("live-a")

    func identity(_ owner: MiniAppID? = nil, generation: UUID = UUID(), registration: UUID = UUID()) throws
        -> MiniAppContinuingIdentity {
        try .init(owner: owner ?? self.owner, localID: "same-id", generation: generation,
                  registrationID: registration)
    }

    func coordinator(journal: JournalBox, driver: FakeDriver, current: UUID)
        -> MiniAppLiveActivityCoordinator<FakeDriver> {
        .init(owner: owner, gate: .init(), journal: journal.access(), native: driver) { identity in
            guard identity.generation == current else { throw MiniAppLiveActivityError.staleIdentity }
        }
    }

    func testConcurrentStartRegistersOnlyOnce() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let service = coordinator(journal: journal, driver: driver, current: generation)
        let key = try identity(generation: generation)
        async let first = service.start(identity: key, content: Content(value: 1))
        async let second = service.start(identity: key, content: Content(value: 1))
        let descriptors = try await [first, second]
        XCTAssertEqual(descriptors.map(\.systemID), ["os-1", "os-1"])
        let requestCount = await driver.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testOldGenerationAndRegistrationCannotUpdateCurrentActivity() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let service = coordinator(journal: journal, driver: driver, current: generation)
        let current = try await service.start(identity: identity(generation: generation), content: .init(value: 1))
        let old = MiniAppLiveActivityDescriptor(identity: try identity(generation: UUID()),
                                                 systemID: current.systemID, content: Content(value: 1))
        await XCTAssertThrowsErrorAsync { _ = try await service.update(old, content: .init(value: 2)) }
        let wrongRegistration = MiniAppLiveActivityDescriptor(
            identity: try identity(generation: generation, registration: UUID()),
            systemID: current.systemID, content: Content(value: 1))
        await XCTAssertThrowsErrorAsync { _ = try await service.update(wrongRegistration, content: .init(value: 2)) }
    }

    func testStartSaveFailureKeepsPendingAndColdReconcileRepairsIt() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let service = coordinator(journal: journal, driver: driver, current: generation)
        let key = try identity(generation: generation)
        // Fail the second write: native registration exists while starting row remains.
        let access = journal.access()
        let wrapped = MiniAppLiveActivityJournalAccess(read: access.read, update: { mutation in
            let isStarting = try access.read().isEmpty
            try access.update(mutation)
            if isStarting { journal.failNextSave = true }
        })
        let interrupted = MiniAppLiveActivityCoordinator(owner: owner, gate: MiniAppContinuingOperationGate(),
            journal: wrapped, native: driver, admission: { _ in })
        await XCTAssertThrowsErrorAsync { _ = try await interrupted.start(identity: key, content: .init(value: 1)) }
        XCTAssertNil(journal.rows.first?.systemID)
        try await service.reconcile()
        XCTAssertEqual(journal.rows.first?.systemID, "os-1")
        XCTAssertEqual(journal.rows.first?.phase, .active)
    }

    func testUnresolvedUpdateAndEndAreReportedAndEndingRowIsRetained() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let service = coordinator(journal: journal, driver: driver, current: generation)
        let descriptor = try await service.start(identity: identity(generation: generation), content: .init(value: 1))
        await driver.setResolveUpdate(false)
        await XCTAssertThrowsErrorAsync { _ = try await service.update(descriptor, content: .init(value: 2)) }
        await driver.setResolveEnd(false)
        await XCTAssertThrowsErrorAsync { try await service.end(descriptor, finalContent: .init(value: 3), immediately: true) }
        XCTAssertEqual(journal.rows.first?.phase, .ending)
    }

    func testEndOwnedDoesNotTouchOtherOwner() async throws {
        let journal = JournalBox(), driver = FakeDriver(), generation = UUID()
        let service = coordinator(journal: journal, driver: driver, current: generation)
        _ = try await service.start(identity: identity(generation: generation), content: .init(value: 1))
        let foreign = try identity(MiniAppID("live-b"), generation: UUID())
        _ = try await driver.request(identity: foreign, content: .init(value: 9))
        await service.close()
        try await service.endOwned { _ in .init(value: 0) }
        let records = await driver.records()
        XCTAssertEqual(records.first(where: { $0.identity.owner == "live-a" })?.state, .dismissed)
        XCTAssertEqual(records.first(where: { $0.identity.owner == "live-b" })?.state, .active)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T, file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { }
}
