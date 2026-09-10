#if canImport(CoreSpotlight)
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import XCTest
import JibunKitCore

final class MiniAppSpotlightTests: XCTestCase {
    func testSameLocalIdentifierGetsOwnedNativeIdentifiersAndAttributes() {
        let a = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-a")))
        let b = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-b")))
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "Native title"
        attributes.keywords = ["native", "metadata"]

        let aItem = a.searchableItem(localIdentifier: "same", attributes: attributes)
        let bItem = b.searchableItem(localIdentifier: "same", attributes: attributes)

        XCTAssertNotEqual(aItem.uniqueIdentifier, bItem.uniqueIdentifier)
        XCTAssertEqual(aItem.domainIdentifier, a.domainIdentifier)
        XCTAssertEqual(bItem.domainIdentifier, b.domainIdentifier)
        XCTAssertTrue(a.owns(itemIdentifier: aItem.uniqueIdentifier))
        XCTAssertFalse(a.owns(itemIdentifier: bItem.uniqueIdentifier))
        XCTAssertEqual(aItem.attributeSet.title, "Native title")
        XCTAssertEqual(aItem.attributeSet.keywords, ["native", "metadata"])
    }

    #if os(iOS)
    func testNativeIndexKeepsOtherOwnerAfterOwnedDomainDeletion() async throws {
        let suffix = UUID().uuidString
        let index = CSSearchableIndex.default()
        let a = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-a")))
        let b = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-b")))
        let localIdentifier = "same-local-id-\(suffix)"
        let aAttributes = CSSearchableItemAttributeSet(contentType: .text)
        aAttributes.title = "A \(suffix)"
        aAttributes.textContent = "owner-a native metadata"
        let bAttributes = CSSearchableItemAttributeSet(contentType: .text)
        bAttributes.title = "B \(suffix)"
        bAttributes.textContent = "owner-b native metadata"

        try await a.index(localIdentifier: localIdentifier, attributes: aAttributes, in: index)
        try await b.index(localIdentifier: localIdentifier, attributes: bAttributes, in: index)

        let expectedIdentifiers = Set([
            a.itemIdentifier(for: localIdentifier),
            b.itemIdentifier(for: localIdentifier),
        ])
        let before = try await waitForItems(identifiers: Array(expectedIdentifiers)) {
            Set($0.map(\.uniqueIdentifier)) == expectedIdentifiers
        }
        XCTAssertEqual(Set(before.map(\.uniqueIdentifier)), expectedIdentifiers)
        let nativeMetadata = Dictionary(uniqueKeysWithValues: before.compactMap { item -> (String, String)? in
            guard let domain = item.domainIdentifier,
                  let text = item.attributeSet.textContent else { return nil }
            return (domain, text)
        })
        XCTAssertEqual(nativeMetadata, [
            a.domainIdentifier: "owner-a native metadata",
            b.domainIdentifier: "owner-b native metadata",
        ])

        try await a.deleteAll(from: index)

        let after = try await waitForItems(identifiers: [
            a.itemIdentifier(for: localIdentifier),
            b.itemIdentifier(for: localIdentifier),
        ]) { $0.map(\.uniqueIdentifier) == [b.itemIdentifier(for: localIdentifier)] }
        XCTAssertEqual(after.map(\.uniqueIdentifier), [b.itemIdentifier(for: localIdentifier)])
        XCTAssertEqual(after.first?.domainIdentifier, b.domainIdentifier)
        XCTAssertEqual(after.first?.attributeSet.textContent, "owner-b native metadata")
        try await b.deleteAll(from: index)
    }

    private func waitForItems(
        identifiers: [String],
        predicate: ([CSSearchableItem]) -> Bool
    ) async throws -> [CSSearchableItem] {
        for _ in 0..<20 {
            let items = try await queryItems(identifiers: identifiers)
            if predicate(items) { return items }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return try await queryItems(identifiers: identifiers)
    }

    private func queryItems(identifiers: [String]) async throws -> [CSSearchableItem] {
        let clauses = identifiers.map { "uniqueIdentifier == '\($0)'" }.joined(separator: " || ")
        return try await withCheckedThrowingContinuation { continuation in
            let query = CSSearchQuery(queryString: clauses, queryContext: nil)
            let items = SearchResults()
            query.foundItemsHandler = { items.append($0) }
            query.completionHandler = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: items.snapshot())
                }
            }
            query.start()
        }
    }
    #endif
}

#if os(iOS)
private final class SearchResults: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CSSearchableItem] = []

    func append(_ newItems: [CSSearchableItem]) {
        lock.withLock { items.append(contentsOf: newItems) }
    }

    func snapshot() -> [CSSearchableItem] {
        lock.withLock { items }
    }
}
#endif
#endif
