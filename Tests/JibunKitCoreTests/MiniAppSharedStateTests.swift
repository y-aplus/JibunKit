import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppSharedStateTests: XCTestCase {
    private struct Value: Codable, Equatable, Sendable {
        var items: [String: Int]
    }
    private enum Injected: Error { case failed }
    private let a = MiniAppID("shared-a")
    private let b = MiniAppID("shared-b")

    private func fixture() throws -> (URL, MiniAppSharedState<Value>, MiniAppSharedState<Value>) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try MiniAppSharedState<Value>(owner: a, containerURL: directory)
        let second = try MiniAppSharedState<Value>(owner: b, containerURL: directory)
        try first.initialize(Value(items: ["same-id": 10, "other-id": 3]), enabled: true)
        try second.initialize(Value(items: ["same-id": 20]), enabled: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return (directory, first, second)
    }

    private func stateURL(_ root: URL, owner: MiniAppID) -> URL {
        root.appendingPathComponent("Library/Application Support/JibunKit/SharedState/" + owner.storageNamespace + ".json")
    }

    func testTargetedUpdateAndReconstructedStoreKeepOtherOwnerAndItem() throws {
        let (root, first, second) = try fixture()
        let snapshot = try first.read()
        let result = try first.update(generation: snapshot.generation) { value in
            value.items["same-id", default: 0] += 4
            return value.items["same-id"]
        }
        XCTAssertEqual(result, 14)
        let reopened = try MiniAppSharedState<Value>(owner: a, containerURL: root)
        XCTAssertEqual(try reopened.read().value.items, ["same-id": 14, "other-id": 3])
        XCTAssertEqual(try second.read().value.items, ["same-id": 20])
        try reopened.initialize(Value(items: [:]), enabled: true)
        XCTAssertEqual(try reopened.read().value.items["same-id"], 14)
    }

    func testFailedMutationPreservesExactBytesAndCanRetry() throws {
        let (root, first, second) = try fixture()
        let snapshot = try first.read()
        let prior = try Data(contentsOf: stateURL(root, owner: a))
        XCTAssertThrowsError(try first.update(generation: snapshot.generation) { value in
            value.items.removeAll()
            throw Injected.failed
        })
        XCTAssertEqual(try Data(contentsOf: stateURL(root, owner: a)), prior)
        try first.update(generation: snapshot.generation) { $0.items["same-id"] = 11 }
        XCTAssertEqual(try first.read().value.items["same-id"], 11)
        XCTAssertEqual(try second.read().value.items["same-id"], 20)
    }

    func testDisableRejectsWritesAndKeepsDataForReenable() throws {
        let (_, first, second) = try fixture()
        let snapshot = try first.read()
        try first.setEnabled(false)
        XCTAssertThrowsError(try first.read())
        XCTAssertThrowsError(try first.update(generation: snapshot.generation) { $0.items.removeAll() })
        try first.initialize(Value(items: [:]), enabled: true)
        XCTAssertThrowsError(try first.read(), "initialize must not re-enable saved disabled state")
        try first.setEnabled(true)
        XCTAssertEqual(try first.read().value, snapshot.value)
        XCTAssertEqual(try second.read().value.items["same-id"], 20)
    }

    func testRemovalTombstoneRejectsSeedAndOldActionAfterReregistration() throws {
        let (_, first, second) = try fixture()
        let old = try first.read()
        XCTAssertThrowsError(try first.remove(), "deletion requires closed admission")
        try first.setEnabled(false)
        try first.remove()
        try first.remove() // Cleanup can retry without reopening admission.
        try first.initialize(Value(items: ["same-id": 999]), enabled: true)
        XCTAssertThrowsError(try first.setEnabled(true))
        try first.replaceWhileDisabled(Value(items: ["same-id": 1]))
        try first.setEnabled(true)
        XCTAssertThrowsError(try first.update(generation: old.generation) { $0.items["same-id"] = 999 }) {
            XCTAssertEqual($0 as? MiniAppSharedStateError, .staleGeneration)
        }
        XCTAssertEqual(try first.read().value.items["same-id"], 1)
        XCTAssertEqual(try second.read().value.items["same-id"], 20)
    }

    func testRestoreRequiresClosedAdmissionAndRejectsPreviousGeneration() throws {
        let (_, first, _) = try fixture()
        let old = try first.read()
        XCTAssertThrowsError(try first.replaceWhileDisabled(Value(items: [:])))
        try first.setEnabled(false)
        try first.replaceWhileDisabled(Value(items: ["same-id": 30]))
        XCTAssertThrowsError(try first.read())
        try first.setEnabled(true)
        XCTAssertThrowsError(try first.update(generation: old.generation) { $0.items.removeAll() })
        XCTAssertEqual(try first.read().value.items["same-id"], 30)
    }

    func testCorruptionIsNotTreatedAsMissingOrRepairedByOrdinaryAccess() throws {
        let (root, first, second) = try fixture()
        let url = stateURL(root, owner: a)
        let bad = Data("{broken".utf8)
        try bad.write(to: url)
        XCTAssertThrowsError(try first.read())
        XCTAssertThrowsError(try first.initialize(Value(items: [:]), enabled: true))
        XCTAssertThrowsError(try first.setEnabled(false))
        XCTAssertEqual(try Data(contentsOf: url), bad)
        XCTAssertEqual(try second.read().value.items["same-id"], 20)
    }

    func testOwnerMismatchCannotApplyAnotherOwnersEnvelope() throws {
        let (root, first, second) = try fixture()
        let otherBytes = try Data(contentsOf: stateURL(root, owner: b))
        try otherBytes.write(to: stateURL(root, owner: a))
        XCTAssertThrowsError(try first.read()) {
            XCTAssertEqual($0 as? MiniAppSharedStateError, .invalidState)
        }
        XCTAssertEqual(try second.read().value.items["same-id"], 20)
    }

    func testOptionalNilPayloadIsDistinctFromDeletion() throws {
        let (root, _, _) = try fixture()
        let store = try MiniAppSharedState<Int?>(owner: MiniAppID("optional"), containerURL: root)
        try store.initialize(nil, enabled: true)
        let snapshot = try store.read()
        XCTAssertNil(snapshot.value)
        try store.update(generation: snapshot.generation) { $0 = 5 }
        XCTAssertEqual(try store.read().value, 5)
    }

    func testMissingStoreDoesNotCreateStateOnReadOrMutation() throws {
        let (root, _, _) = try fixture()
        let missing = MiniAppID("missing")
        let store = try MiniAppSharedState<Value>(owner: missing, containerURL: root)
        XCTAssertThrowsError(try store.read())
        XCTAssertThrowsError(try store.update(generation: UUID()) { $0.items.removeAll() })
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL(root, owner: missing).path))
    }
}
#endif
