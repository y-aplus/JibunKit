import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppIncomingDeliveryTests: XCTestCase, @unchecked Sendable {
    private enum Fault: Error { case receiver }
    private let a = MiniAppID("delivery-a")
    private let b = MiniAppID("delivery-b")

    private func fixture() throws -> (URL, MiniAppIncomingStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = try MiniAppIncomingStore(containerURL: root)
        try inbox.publish([a, b].map { .init(id: $0, title: $0.rawValue, typeIdentifiers: ["public.data"]) })
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return (root, inbox)
    }

    @MainActor
    func testFailedReceiverKeepsReceiptAndRetryUsesSameIDWithoutTouchingB() async throws {
        let (root, inbox) = try fixture()
        let source = root.appendingPathComponent("source.txt")
        try Data("incoming bytes".utf8).write(to: source)
        let receipt = try inbox.enqueue(for: a, inputs: [.file(source, typeIdentifier: "public.plain-text", displayName: "source.txt")])
        let other = try inbox.enqueue(for: b, inputs: [.text("B")])
        let delivery = MiniAppIncomingDelivery()
        let failing = MiniAppIncomingProvider(id: a, typeIdentifiers: ["public.data"]) { value, directory in
            XCTAssertEqual(value.id, receipt.id)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(value.items[0].value)), Data("incoming bytes".utf8))
            throw Fault.receiver
        }
        do {
            try await delivery.deliver(id: receipt.id, provider: failing, lifetime: nil, inbox: inbox)
            XCTFail("Receiver failure must propagate")
        } catch is Fault { }
        XCTAssertEqual(try inbox.pending(for: a).receipts, [receipt])
        let retry = MiniAppIncomingProvider(id: a, typeIdentifiers: ["public.data"]) { value, directory in
            XCTAssertEqual(value.id, receipt.id)
            try Data(contentsOf: directory.appendingPathComponent(value.items[0].value)).write(to: root.appendingPathComponent("saved.txt"), options: .atomic)
        }
        try await delivery.deliver(id: receipt.id, provider: retry, lifetime: nil, inbox: inbox)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("saved.txt")), Data("incoming bytes".utf8))
        XCTAssertTrue(try inbox.pending(for: a).receipts.isEmpty)
        XCTAssertEqual(try inbox.pending(for: b).receipts, [other])
    }

    @MainActor
    func testCancellationPreservesReceiptAndBlocksCrossSceneDiscardAndDuplicateApply() async throws {
        let (_, inbox) = try fixture()
        let receipt = try inbox.enqueue(for: a, inputs: [.text("A")])
        let delivery = MiniAppIncomingDelivery()
        let entered = expectation(description: "receiver entered")
        let provider = MiniAppIncomingProvider(id: a, typeIdentifiers: ["public.data"]) { _, _ in
            entered.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        let task = Task { try await delivery.deliver(id: receipt.id, provider: provider, lifetime: nil, inbox: inbox) }
        await fulfillment(of: [entered], timeout: 5)
        do {
            try await delivery.discard(id: receipt.id, owner: a, inbox: inbox)
            XCTFail("Other scene discarded an active receipt")
        } catch MiniAppIncomingDelivery.Failure.alreadyDelivering { }
        do {
            try await delivery.deliver(id: receipt.id, provider: provider, lifetime: nil, inbox: inbox)
            XCTFail("Other scene applied the same receipt")
        } catch MiniAppIncomingDelivery.Failure.alreadyDelivering { }
        task.cancel()
        do { try await task.value; XCTFail("Cancellation was hidden") }
        catch is CancellationError { }
        XCTAssertEqual(try inbox.pending(for: a).receipts, [receipt])
        try await delivery.discard(id: receipt.id, owner: a, inbox: inbox)
        XCTAssertTrue(try inbox.pending(for: a).receipts.isEmpty)
    }

    @MainActor
    func testCancellationAfterReceiverCommitAcknowledgesSuccessAndPreservesB() async throws {
        let (root, inbox) = try fixture()
        let receipt = try inbox.enqueue(for: a, inputs: [.text("A")])
        let other = try inbox.enqueue(for: b, inputs: [.text("B")])
        let committed = expectation(description: "receiver committed before cancellation")
        let saved = root.appendingPathComponent("committed.txt")
        let provider = MiniAppIncomingProvider(id: a, typeIdentifiers: ["public.data"]) { _, _ in
            try Data("committed".utf8).write(to: saved, options: .atomic)
            committed.fulfill()
            // This receiver has already committed, so late cancellation cannot
            // turn its result into a failed transaction or leave a retry pending.
            do { try await Task.sleep(nanoseconds: 60_000_000_000) }
            catch is CancellationError { }
        }
        let delivery = MiniAppIncomingDelivery()
        let task = Task { try await delivery.deliver(id: receipt.id, provider: provider, lifetime: nil, inbox: inbox) }
        await fulfillment(of: [committed], timeout: 5)
        task.cancel()
        try await task.value
        XCTAssertEqual(try Data(contentsOf: saved), Data("committed".utf8))
        XCTAssertTrue(try inbox.pending(for: a).receipts.isEmpty)
        XCTAssertEqual(try inbox.pending(for: b).receipts, [other])
    }

    @MainActor
    func testDisabledOwnerCannotInvokeReceiverWhileOtherOwnerStillWorks() async throws {
        let (_, inbox) = try fixture()
        let first = try inbox.enqueue(for: a, inputs: [.text("A")])
        let other = try inbox.enqueue(for: b, inputs: [.text("B")])
        let coordinator = MiniAppRestoreCoordinator()
        coordinator.setAccessAllowed(false, for: a)
        let provider = MiniAppIncomingProvider(id: a, typeIdentifiers: ["public.data"]) { _, _ in XCTFail("Disabled owner ran") }
        let delivery = MiniAppIncomingDelivery()
        do {
            try await delivery.deliver(id: first.id, provider: provider, lifetime: nil, inbox: inbox, coordinator: coordinator)
            XCTFail("Disabled owner admitted")
        } catch is MiniAppRestoreCoordinator.Unavailable { }
        let enabled = MiniAppIncomingProvider(id: b, typeIdentifiers: ["public.data"]) { _, _ in }
        try await delivery.deliver(id: other.id, provider: enabled, lifetime: nil, inbox: inbox, coordinator: coordinator)
        XCTAssertEqual(try inbox.pending(for: a).receipts, [first])
        XCTAssertTrue(try inbox.pending(for: b).receipts.isEmpty)
    }
}
#endif
