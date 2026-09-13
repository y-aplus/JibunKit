import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppIncomingStoreTests: XCTestCase {
    private let a = MiniAppID("incoming-a")
    private let b = MiniAppID("incoming-b")

    private func fixture() throws -> (URL, MiniAppIncomingStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try MiniAppIncomingStore(containerURL: directory)
        try store.publish([
            .init(id: a, title: "A", typeIdentifiers: ["public.data"]),
            .init(id: b, title: "B", typeIdentifiers: ["public.data"]),
        ])
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return (directory, store)
    }

    func testSourceCanDisappearAfterSuccessfulCopyAndFreshStoreReadsSameReceipt() throws {
        let (directory, store) = try fixture()
        let source = directory.appendingPathComponent("input.txt")
        try Data("external text".utf8).write(to: source)
        let receipt = try store.enqueue(for: a, inputs: [.file(source, typeIdentifier: "public.plain-text", displayName: "input.txt"), .url(URL(string: "https://example.com/note")!)])
        try FileManager.default.removeItem(at: source)
        let reopened = try MiniAppIncomingStore(containerURL: directory)
        XCTAssertEqual(try reopened.pending(for: a).receipts, [receipt])
        try reopened.withReceipt(id: receipt.id, owner: a) { value, folder in
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(value.items[0].value)), Data("external text".utf8))
            XCTAssertEqual(value.items[0].displayName, "input.txt")
            XCTAssertEqual(value.items[1].value, "https://example.com/note")
        }
    }

    func testFailedMixedBatchPublishesNothingAndKeepsExistingOtherOwner() throws {
        let (directory, store) = try fixture()
        let saved = try store.enqueue(for: b, inputs: [.text("B unchanged")])
        XCTAssertThrowsError(try store.enqueue(for: a, inputs: [.text("first"), .file(directory.appendingPathComponent("missing"), typeIdentifier: "public.data", displayName: "missing")]))
        XCTAssertTrue(try store.pending(for: a).receipts.isEmpty)
        XCTAssertEqual(try store.pending(for: b).receipts, [saved])
        let owner = directory.appendingPathComponent("Library/Application Support/JibunKit/Incoming/owners/" + a.storageNamespace)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: owner.path).isEmpty)
    }

    func testAdmissionClosePreservesPendingThenDeletionOnlyRemovesOwner() throws {
        let (_, store) = try fixture()
        let savedA = try store.enqueue(for: a, inputs: [.text("A")])
        let savedB = try store.enqueue(for: b, inputs: [.text("B")])
        XCTAssertThrowsError(try store.removeOwnedData(for: a))
        try store.setAdmission(.init(id: a, title: "A", typeIdentifiers: ["public.data"]), enabled: false)
        XCTAssertThrowsError(try store.enqueue(for: a, inputs: [.text("late")]))
        XCTAssertEqual(try store.pending(for: a).receipts, [savedA])
        try store.removeOwnedData(for: a)
        XCTAssertTrue(try store.pending(for: a).receipts.isEmpty)
        XCTAssertEqual(try store.pending(for: b).receipts, [savedB])
        try store.setAdmission(.init(id: a, title: "A", typeIdentifiers: ["public.data"]), enabled: true)
        _ = try store.enqueue(for: a, inputs: [.text("new")])
        XCTAssertEqual(try store.pending(for: b).receipts, [savedB])
    }

    func testAcknowledgementCannotUseAnotherOwnersReceiptID() throws {
        let (_, store) = try fixture()
        let receipt = try store.enqueue(for: b, inputs: [.text("B")])
        XCTAssertThrowsError(try store.acknowledge(id: receipt.id, owner: a))
        XCTAssertEqual(try store.pending(for: b).receipts, [receipt])
        try store.acknowledge(id: receipt.id, owner: b)
        XCTAssertTrue(try store.pending(for: b).receipts.isEmpty)
    }

    func testCorruptReceiptIsReportedWithoutHidingOtherReceiptAndCanBeDiscarded() throws {
        let (directory, store) = try fixture()
        let broken = try store.enqueue(for: a, inputs: [.text("first")])
        let valid = try store.enqueue(for: a, inputs: [.text("second")])
        let manifest = directory.appendingPathComponent("Library/Application Support/JibunKit/Incoming/owners/" + a.storageNamespace + "/" + broken.id.uuidString + "/receipt.json")
        try Data("{".utf8).write(to: manifest)
        let listing = try store.pending(for: a)
        XCTAssertEqual(listing.receipts, [valid])
        XCTAssertEqual(listing.unreadableIDs, [broken.id])
        XCTAssertThrowsError(try store.acknowledge(id: broken.id, owner: a))
        try store.discard(id: broken.id, owner: a)
        XCTAssertTrue(try store.pending(for: a).unreadableIDs.isEmpty)
    }

    func testSymbolicFileAndOwnerAliasDoNotImportOrDeleteOutsideFiles() throws {
        let (directory, store) = try fixture()
        let external = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let value = external.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: value)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: value)
        XCTAssertThrowsError(try store.enqueue(for: a, inputs: [.file(link, typeIdentifier: "public.data", displayName: "link")]))
        let owner = directory.appendingPathComponent("Library/Application Support/JibunKit/Incoming/owners/" + b.storageNamespace)
        try FileManager.default.createSymbolicLink(at: owner, withDestinationURL: external)
        try store.setAdmission(.init(id: b, title: "B", typeIdentifiers: ["public.data"]), enabled: false)
        XCTAssertThrowsError(try store.removeOwnedData(for: b))
        XCTAssertEqual(try Data(contentsOf: value), Data("keep".utf8))
    }

    func testInvalidCatalogDoesNotReplacePreviouslyPublishedDestinations() throws {
        let (_, store) = try fixture()
        let before = try store.destinations()
        XCTAssertThrowsError(try store.publish([before[0], before[0]]))
        XCTAssertEqual(try store.destinations(), before)
        XCTAssertThrowsError(try store.enqueue(for: MiniAppID("unknown"), inputs: [.text("no")]))
    }

    func testLegalOwnerIDsCannotCollideWithHostCoordinationOrCatalogFiles() throws {
        let (_, store) = try fixture()
        let owners = [MiniAppID("coordination"), MiniAppID("destinations.json")]
        try store.publish(owners.map { .init(id: $0, title: $0.rawValue, typeIdentifiers: ["public.data"]) })
        for owner in owners { _ = try store.enqueue(for: owner, inputs: [.text(owner.rawValue)]) }
        XCTAssertEqual(Set(try store.ownersWithReceipts()), Set(owners))
        for owner in owners { XCTAssertEqual(try store.pending(for: owner).receipts.count, 1) }
        XCTAssertEqual(try store.destinations().count, 2)
    }

    func testAbandonedStagingIsReapedWithoutPublishingPartialData() throws {
        let (directory, store) = try fixture()
        let saved = try store.enqueue(for: a, inputs: [.text("complete")])
        let abandoned = directory.appendingPathComponent("Library/Application Support/JibunKit/Incoming/owners/" + a.storageNamespace + "/.staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: false)
        try Data("partial bytes".utf8).write(to: abandoned.appendingPathComponent("part"))
        XCTAssertEqual(try store.pending(for: a).receipts, [saved])
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
    }

    func testUnsupportedTypeRejectsWholeBatchAndPreservesOtherOwner() throws {
        let (_, store) = try fixture()
        try store.setAdmission(.init(id: a, title: "A", typeIdentifiers: ["public.plain-text"]), enabled: true)
        let saved = try store.enqueue(for: b, inputs: [.text("B")])
        XCTAssertThrowsError(try store.enqueue(for: a, inputs: [.text("first"), .url(URL(string: "https://example.com")!)]))
        XCTAssertTrue(try store.pending(for: a).receipts.isEmpty)
        XCTAssertEqual(try store.pending(for: b).receipts, [saved])
    }
}
#endif
