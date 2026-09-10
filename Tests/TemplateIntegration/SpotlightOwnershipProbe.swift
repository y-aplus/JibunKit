// Included only in the isolated signed CI host, never in a distributed IPA.
import CoreSpotlight
import Foundation
import JibunKitCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class SpotlightOwnershipProbeState {
    var result = "idle"

    func run() async {
        result = "running"
        let suffix = UUID().uuidString
        let index = CSSearchableIndex.default()
        let a = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-a")))
        let b = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("spotlight-b")))
        let localIdentifier = "same-local-id-\(suffix)"
        let aIdentifier = a.itemIdentifier(for: localIdentifier)
        let bIdentifier = b.itemIdentifier(for: localIdentifier)
        let titles = ["A \(suffix)", "B \(suffix)"]

        do {
            let aAttributes = CSSearchableItemAttributeSet(contentType: .text)
            aAttributes.title = titles[0]
            aAttributes.textContent = "owner-a native metadata"
            let bAttributes = CSSearchableItemAttributeSet(contentType: .text)
            bAttributes.title = titles[1]
            bAttributes.textContent = "owner-b native metadata"

            try await a.index(localIdentifier: localIdentifier, attributes: aAttributes, in: index)
            try await b.index(localIdentifier: localIdentifier, attributes: bAttributes, in: index)
            let before = try await SpotlightOwnershipProbe.queryEventually(
                titles: titles, expectedIdentifiers: Set([aIdentifier, bIdentifier]))
            print("SPOTLIGHT_OWNERSHIP queriedBefore=\(SpotlightOwnershipProbe.details(before))")
            guard SpotlightOwnershipProbe.metadata(before) == [
                a.domainIdentifier: "owner-a native metadata",
                b.domainIdentifier: "owner-b native metadata",
            ] else {
                throw SpotlightOwnershipProbe.Failure.unexpectedMetadata
            }

            try await a.deleteAll(from: index)
            let after = try await SpotlightOwnershipProbe.queryEventually(
                titles: titles, expectedIdentifiers: Set([bIdentifier]))
            print("SPOTLIGHT_OWNERSHIP queriedAfter=\(SpotlightOwnershipProbe.details(after))")
            guard SpotlightOwnershipProbe.metadata(after) == [
                b.domainIdentifier: "owner-b native metadata"
            ] else {
                throw SpotlightOwnershipProbe.Failure.unexpectedMetadata
            }

            print("SPOTLIGHT_OWNERSHIP before=\(before.map(\.uniqueIdentifier).sorted())")
            print("SPOTLIGHT_OWNERSHIP deletedDomain=\(a.domainIdentifier)")
            print("SPOTLIGHT_OWNERSHIP after=\(after.map(\.uniqueIdentifier).sorted()) metadata=\(SpotlightOwnershipProbe.metadata(after))")
            result = "passed"
            try await b.deleteAll(from: index)
        } catch {
            print("SPOTLIGHT_OWNERSHIP error=\(error)")
            result = "failed: \(error)"
        }
    }
}

@MainActor
enum SpotlightOwnershipProbe {
    enum Failure: Error {
        case unexpectedItems
        case unexpectedMetadata
    }

    private static let state = SpotlightOwnershipProbeState()
    static let definition = MiniAppDefinition(
        id: MiniAppID("spotlight-probe"), title: "Spotlight probe", systemImage: "magnifyingglass"
    ) { _ in
        VStack {
            Text(state.result).accessibilityIdentifier("spotlight.ownership.result")
            Button("Run Spotlight ownership check") {
                Task { await state.run() }
            }.accessibilityIdentifier("spotlight.ownership.run")
        }
    }

    static func metadata(_ items: [CSSearchableItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let domain = item.domainIdentifier,
                  let text = item.attributeSet.textContent else { return nil }
            return (domain, text)
        })
    }

    static func details(_ items: [CSSearchableItem]) -> [String] {
        items.map {
            "id=\($0.uniqueIdentifier) domain=\($0.domainIdentifier ?? "nil") title=\($0.attributeSet.title ?? "nil") text=\($0.attributeSet.textContent ?? "nil")"
        }.sorted()
    }

    static func queryEventually(
        titles: [String], expectedIdentifiers: Set<String>
    ) async throws -> [CSSearchableItem] {
        for _ in 0..<40 {
            let items = try await query(titles: titles)
            if Set(items.map(\.uniqueIdentifier)) == expectedIdentifiers { return items }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw Failure.unexpectedItems
    }

    private static func query(titles: [String]) async throws -> [CSSearchableItem] {
        let clauses = titles.map { "title == \"\($0)\"" }.joined(separator: " || ")
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["title", "textContent", "domainIdentifier"]
        return try await withCheckedThrowingContinuation { continuation in
            let query = CSSearchQuery(queryString: clauses, queryContext: context)
            let results = SpotlightSearchResults()
            query.foundItemsHandler = { results.append($0) }
            query.completionHandler = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results.snapshot())
                }
            }
            query.start()
        }
    }
}

private final class SpotlightSearchResults: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CSSearchableItem] = []

    func append(_ newItems: [CSSearchableItem]) {
        lock.withLock { items.append(contentsOf: newItems) }
    }

    func snapshot() -> [CSSearchableItem] {
        lock.withLock { items }
    }
}
