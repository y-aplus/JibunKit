#if os(iOS)
import CloudKit
import XCTest
@testable import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2IdentityNativeTests: XCTestCase {
    func testProbePublishesTwoOrdinaryDefinitionsWithoutCreatingCKContainer() {
        let definitions = P2IdentityProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-identity-a"), MiniAppID("p2-identity-b")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.removal != nil })
    }

    func testTwoOwnersKeepSameLocalIDSeparateAcrossRemoval() async throws {
        let backend = P2IdentityBackend(account: "one")
        let (a, b) = try pair(backend)
        _ = try await a.activate(); _ = try await b.activate()
        let ai = try await a.identity(localID: "same"), bi = try await b.identity(localID: "same")
        try await a.save(ai, fields: ["v": "A"]); try await b.save(bi, fields: ["v": "B"])
        try await a.removeOwnedData()
        let deleted = try await a.load(ai), preserved = try await b.load(bi)
        XCTAssertNil(deleted); XCTAssertEqual(preserved?.fields["v"], "B")
    }

    func testAccountReplacementAndLateCompletionCannotPublishOldResult() async throws {
        let backend = P2IdentityBackend(account: "old"), (a, _) = try pair(backend)
        _ = try await a.activate(); let old = try await a.identity(localID: "same")
        try await a.save(old, fields: ["v": "old"]); await backend.hold()
        let late = Task { try await a.load(old) }
        await backend.waitForHold(); await backend.changeAccount("new")
        _ = try await a.accountDidChange(); await backend.release()
        await XCTAssertThrowsErrorAsync { try await late.value }
        let fresh = try await a.identity(localID: "same")
        try await a.save(fresh, fields: ["v": "new"])
        let value = try await a.load(fresh)
        XCTAssertEqual(value?.fields["v"], "new")
    }

    func testFailureThenRecoveryLeavesOtherOwnerRunning() async throws {
        let backend = P2IdentityBackend(account: "one"), (a, b) = try pair(backend)
        _ = try await b.activate(); let bi = try await b.identity(localID: "same")
        try await b.save(bi, fields: ["v": "B"]); await backend.failOnce()
        await XCTAssertThrowsErrorAsync { try await a.activate() }
        _ = try await a.activate()
        let preserved = try await b.load(bi)
        XCTAssertEqual(preserved?.fields["v"], "B")
    }

    /// This is the only real-OS path. It is skipped unless a signed test host explicitly
    /// supplies its entitled container identifier. Fake-backend tests never satisfy it.
    func testEntitledCloudKitRoundTripWhenExplicitlyConfigured() async throws {
        let key = "JIBUNKIT_CLOUDKIT_CONTAINER"
        guard let identifier = ProcessInfo.processInfo.environment[key], !identifier.isEmpty else {
            throw XCTSkip("\(key) is absent; no real CloudKit communication was attempted")
        }
        let container = CKContainer(identifier: identifier)
        let scope = try MiniAppExternalContainer(identifier: identifier)
        let backend = CloudKitExternalIdentityBackend(container: container)
        let coordinator = MiniAppExternalIdentityCoordinator(owner: MiniAppID("p2-native-cloudkit"),
                                                              container: scope, backend: backend)
        _ = try await coordinator.activate()
        let record = try await coordinator.identity(localID: "signed-roundtrip")
        let nonce = UUID().uuidString
        try await coordinator.save(record, fields: ["nonce": nonce])
        let fetched = try await coordinator.load(record)
        XCTAssertEqual(fetched?.fields["nonce"], nonce)
        try await coordinator.delete(record)
    }

    private func pair(_ backend: P2IdentityBackend) throws
        -> (MiniAppExternalIdentityCoordinator, MiniAppExternalIdentityCoordinator) {
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        return (.init(owner: MiniAppID("native-a"), container: scope, backend: backend),
                .init(owner: MiniAppID("native-b"), container: scope, backend: backend))
    }
}

private actor P2IdentityBackend: MiniAppExternalIdentityBackend {
    enum Failure: Error { case injected }
    var account: String; var records: [MiniAppExternalRecordIdentity: MiniAppExternalRecord] = [:]
    var failing = false, holding = false
    var held: CheckedContinuation<Void, Never>?, observed: CheckedContinuation<Void, Never>?
    init(account: String) { self.account = account }
    func changeAccount(_ value: String) { account = value }
    func failOnce() { failing = true }
    func hold() { holding = true }
    func waitForHold() async { if held == nil { await withCheckedContinuation { observed = $0 } } }
    func release() { held?.resume(); held = nil }
    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        if failing { failing = false; throw Failure.injected }; return account
    }
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        if holding { holding = false; await withCheckedContinuation { held = $0; observed?.resume(); observed = nil } }
        return records[identity]
    }
    func save(_ record: MiniAppExternalRecord) async throws { records[record.identity] = record }
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws { records[identity] = nil }
    func ensureSubscription(for account: MiniAppExternalAccount) async throws {}
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        records = records.filter { $0.key.account != account }
    }
    func cancelOperations(owner: MiniAppID) async {}
}

private func XCTAssertThrowsErrorAsync<T>(_ operation: () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await operation(); XCTFail("Expected error", file: file, line: line) } catch {}
}
#endif
