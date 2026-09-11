import AppIntents
import IntentFeatureA
import IntentFeatureB
import XCTest

@MainActor
final class IntentExecutionTests: XCTestCase {
    func testSameNamedEntityQueriesResolveOnlyTheirOwner() async throws {
        IntentFeatureA.EntryStore.titles = ["shared-id": "A first", "a-only": "A extra"]
        IntentFeatureB.EntryStore.titles = ["shared-id": "B first", "b-only": "B extra"]
        defer {
            IntentFeatureA.EntryStore.titles = [:]
            IntentFeatureB.EntryStore.titles = [:]
        }
        let a = try await IntentFeatureA.Entry.defaultQuery.entities(for: ["shared-id", "b-only", "missing"])
        let b = try await IntentFeatureB.Entry.defaultQuery.entities(for: ["shared-id", "a-only", "missing"])
        XCTAssertEqual(a.map(\.id), ["shared-id"])
        XCTAssertEqual(b.map(\.id), ["shared-id"])
        XCTAssertEqual(a.map(\.title), ["A first"])
        XCTAssertEqual(b.map(\.title), ["B first"])
        let aSearch = try await IntentFeatureA.EntryQuery().entities(matching: "FIRST")
        let bSearch = try await IntentFeatureB.EntryQuery().entities(matching: "first")
        XCTAssertEqual(aSearch.map(\.title), ["A first"])
        XCTAssertEqual(bSearch.map(\.title), ["B first"])
        let aSuggestions = try await IntentFeatureA.EntryQuery().suggestedEntities()
        let bSuggestions = try await IntentFeatureB.EntryQuery().suggestedEntities()
        XCTAssertEqual(aSuggestions.map(\.id), ["a-only", "shared-id"])
        XCTAssertEqual(bSuggestions.map(\.id), ["b-only", "shared-id"])

        // Saved entities contain an old display value; execution resolves the
        // current record by stable ID instead of using that stale snapshot.
        let savedA = try XCTUnwrap(a.first)
        let savedB = try XCTUnwrap(b.first)
        IntentFeatureA.EntryStore.titles["shared-id"] = "A changed"
        let readA = try await FeatureAReadEntryIntent(entry: savedA).perform()
        let readB = try await FeatureBReadEntryIntent(entry: savedB).perform()
        XCTAssertEqual(readA.value, "A changed")
        XCTAssertEqual(readB.value, "B first")
        IntentFeatureA.EntryStore.titles.removeValue(forKey: "shared-id")
        let removed = try await IntentFeatureA.EntryQuery().entities(for: ["shared-id"])
        XCTAssertTrue(removed.isEmpty)
        do {
            _ = try await FeatureAReadEntryIntent(entry: savedA).perform()
            XCTFail("Deleted A entity must not resolve to B's matching local ID")
        } catch FeatureAReadEntryIntent.Failure.missingEntry {
            // Expected application-level deleted-record behavior.
        }
        let survivingB = try await FeatureBReadEntryIntent(entry: savedB).perform()
        XCTAssertEqual(survivingB.value, "B first")
        XCTAssertEqual(IntentFeatureB.EntryStore.titles.count, 2)
    }

    func testPackageIntentExecutionChangesOnlyItsOwner() async throws {
        FeatureAValues.value = 10
        FeatureBValues.value = 100
        defer { FeatureAValues.value = 0; FeatureBValues.value = 0 }
        let a = try await FeatureAAddValueIntent(amount: 3).perform()
        XCTAssertEqual(a.value, 13)
        XCTAssertEqual(FeatureAValues.value, 13)
        XCTAssertEqual(FeatureBValues.value, 100)
        let b = try await FeatureBAddValueIntent(amount: -7).perform()
        XCTAssertEqual(b.value, 93)
        XCTAssertEqual(FeatureAValues.value, 13)
        XCTAssertEqual(FeatureBValues.value, 93)
    }
}
