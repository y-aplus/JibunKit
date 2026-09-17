import XCTest
@testable import JibunKitCore

final class MiniAppExternalIdentityCoordinatorTests: XCTestCase {
    func testSameLocalIDIsSeparatedForTwoOwnersAndRemovingOneKeepsOther() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account-1")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-b"), container: scope, backend: backend)
        _ = try await a.activate(); _ = try await b.activate()
        let aID = try await a.identity(localID: "same")
        let bID = try await b.identity(localID: "same")
        try await a.save(aID, fields: ["value": "A"])
        try await b.save(bID, fields: ["value": "B"])
        try await a.removeOwnedData()
        let deleted = try await a.load(aID)
        let preserved = try await b.load(bID)
        XCTAssertNil(deleted)
        XCTAssertEqual(preserved?.fields["value"], "B")
    }

    func testAccountChangeRejectsOldIdentityAndPreservesNewAccountValue() async throws {
        let backend = ExternalIdentityFakeBackend(account: "old")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let old = try await sut.identity(localID: "item")
        try await sut.save(old, fields: ["value": "old"])
        await backend.setAccount("new")
        let changed = try await sut.accountDidChange()
        XCTAssertEqual(changed.accountIdentifier, "new")
        await XCTAssertThrowsExternal(.staleGeneration) { try await sut.load(old) }
        let new = try await sut.identity(localID: "item")
        try await sut.save(new, fields: ["value": "new"])
        let result = try await sut.load(new)
        XCTAssertEqual(result?.fields["value"], "new")
    }

    func testLateResultAfterAccountChangeIsRejected() async throws {
        let backend = ExternalIdentityFakeBackend(account: "old")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let old = try await sut.identity(localID: "slow")
        try await sut.save(old, fields: ["value": "old"])
        await backend.holdNextLoad()
        let late = Task { try await sut.load(old) }
        await backend.waitUntilLoadIsHeld()
        await backend.setAccount("new")
        _ = try await sut.accountDidChange()
        await backend.releaseLoad()
        await XCTAssertThrowsExternal(.staleGeneration) { try await late.value }
    }

    func testDeactivateRejectsLateResult() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let identity = try await sut.identity(localID: "slow")
        try await sut.save(identity, fields: ["value": "kept"])
        await backend.holdNextLoad()
        let late = Task { try await sut.load(identity) }
        await backend.waitUntilLoadIsHeld()
        await sut.deactivate(); await backend.releaseLoad()
        await XCTAssertThrowsExternal(.staleGeneration) { try await late.value }
    }

    func testActivationFailureCanRecoverWithoutAffectingOtherOwner() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-b"), container: scope, backend: backend)
        _ = try await b.activate()
        let bID = try await b.identity(localID: "same")
        try await b.save(bID, fields: ["value": "B"])
        await backend.failNextAccountLookup()
        await XCTAssertThrowsExternal(nil) { try await a.activate() }
        _ = try await a.activate()
        let preserved = try await b.load(bID)
        XCTAssertEqual(preserved?.fields["value"], "B")
    }

    @MainActor
    func testFeatureLifetimeStopAndRestartInvalidatesOnlyItsOwner() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityFeature(id: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityFeature(id: MiniAppID("owner-b"), container: scope, backend: backend)
        try await a.lifetime.start(); try await b.lifetime.start()
        let bRuntime = b.lifetime.runtime
        let oldA = try await a.coordinator.identity(localID: "same")
        let bID = try await b.coordinator.identity(localID: "same")
        try await b.coordinator.save(bID, fields: ["value": "B"])
        await a.lifetime.stop()
        XCTAssertTrue(b.lifetime.runtime === bRuntime)
        do { _ = try await a.coordinator.load(oldA); XCTFail("Expected stale generation") }
        catch let error as MiniAppExternalIdentityError { XCTAssertEqual(error, .staleGeneration) }
        let preserved = try await b.coordinator.load(bID)
        XCTAssertEqual(preserved?.fields["value"], "B")
        try await a.lifetime.start()
        let newA = try await a.coordinator.identity(localID: "same")
        XCTAssertNotEqual(oldA.account.generation, newA.account.generation)
        await b.lifetime.stop(); await a.lifetime.stop()
    }

    private func coordinator(_ backend: ExternalIdentityFakeBackend) throws -> MiniAppExternalIdentityCoordinator {
        MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"),
            container: try .init(identifier: "iCloud.test"), backend: backend)
    }
}

private actor ExternalIdentityFakeBackend: MiniAppExternalIdentityBackend {
    enum Failure: Error { case injected }
    private var account: String
    private var rows: [MiniAppExternalRecordIdentity: MiniAppExternalRecord] = [:]
    private var failAccount = false
    private var shouldHoldLoad = false
    private var heldLoad: CheckedContinuation<Void, Never>?
    private var holdObserved: CheckedContinuation<Void, Never>?

    init(account: String) { self.account = account }
    func setAccount(_ value: String) { account = value }
    func failNextAccountLookup() { failAccount = true }
    func holdNextLoad() { shouldHoldLoad = true }
    func waitUntilLoadIsHeld() async {
        if heldLoad == nil { await withCheckedContinuation { holdObserved = $0 } }
    }
    func releaseLoad() { heldLoad?.resume(); heldLoad = nil }

    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        if failAccount { failAccount = false; throw Failure.injected }
        return account
    }
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        if shouldHoldLoad {
            shouldHoldLoad = false
            await withCheckedContinuation { continuation in
                heldLoad = continuation; holdObserved?.resume(); holdObserved = nil
            }
        }
        return rows[identity]
    }
    func save(_ record: MiniAppExternalRecord) async throws { rows[record.identity] = record }
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws { rows[identity] = nil }
    func ensureSubscription(for account: MiniAppExternalAccount) async throws {}
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        rows = rows.filter { $0.key.account != account }
    }
    func cancelOperations(owner: MiniAppID) async {}
}

private func XCTAssertThrowsExternal<T>(_ expected: MiniAppExternalIdentityError?,
    _ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await operation(); XCTFail("Expected error", file: file, line: line) }
    catch let error as MiniAppExternalIdentityError {
        if let expected { XCTAssertEqual(error, expected, file: file, line: line) }
    } catch { if expected != nil { XCTFail("Unexpected error: \(error)", file: file, line: line) } }
}
