import AppIntents
import IntentFeatureA
import IntentFeatureB
import JibunKitCore
import XCTest

final class IntentExecutionTests: XCTestCase, @unchecked Sendable {
    override func setUp() async throws { try await resetStores() }

    @MainActor
    private func resetStores() async throws {
        let defaults = IntentFixtureIntegration.defaults
        for id in [MiniAppID.intentFixtureA, .intentFixtureB] {
            defaults.removeObject(forKey: MiniAppManagement.defaultStorageKey + "." + id.rawValue)
        }
        IntentFixtureIntegration.reconstructManagement()
        try await IntentFeatureA.FeatureAStore.shared.removeAll()
        try await IntentFeatureB.FeatureBStore.shared.removeAll()
    }

    @MainActor
    func testSameNamedEntityQueriesResolveOnlyTheirOwner() async throws {
        try await IntentFeatureA.FeatureAStore.shared.replaceEntries(["shared-id": "A first", "a-only": "A extra"])
        try await IntentFeatureB.FeatureBStore.shared.replaceEntries(["shared-id": "B first", "b-only": "B extra"])
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
        try await IntentFeatureA.FeatureAStore.shared.replaceEntries(["shared-id": "A changed", "a-only": "A extra"])
        let readA = try await IntentFeatureA.ReadEntryIntent(entry: savedA).perform()
        let readB = try await IntentFeatureB.ReadEntryIntent(entry: savedB).perform()
        XCTAssertEqual(readA.value, "A changed")
        XCTAssertEqual(readB.value, "B first")
        try await IntentFeatureA.FeatureAStore.shared.replaceEntries(["a-only": "A extra"])
        let removed = try await IntentFeatureA.EntryQuery().entities(for: ["shared-id"])
        XCTAssertTrue(removed.isEmpty)
        do {
            _ = try await IntentFeatureA.ReadEntryIntent(entry: savedA).perform()
            XCTFail("Deleted A entity must not resolve to B's matching local ID")
        } catch IntentFeatureA.ReadEntryIntent.Failure.missingEntry {
            // Expected application-level deleted-record behavior.
        }
        let survivingB = try await IntentFeatureB.ReadEntryIntent(entry: savedB).perform()
        XCTAssertEqual(survivingB.value, "B first")
        let survivingEntries = try await IntentFeatureB.FeatureBStore.shared.entries()
        XCTAssertEqual(survivingEntries.count, 2)
    }

    @MainActor
    func testPackageIntentExecutionChangesOnlyItsOwner() async throws {
        _ = try await IntentFeatureA.FeatureAStore.shared.add(10)
        _ = try await IntentFeatureB.FeatureBStore.shared.add(100)
        let a = try await FeatureAAddValueIntent(amount: 3).perform()
        XCTAssertEqual(a.value, 13)
        var storedA = try await IntentFeatureA.FeatureAStore.shared.value()
        var storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(storedA, 13)
        XCTAssertEqual(storedB, 100)
        let b = try await FeatureBAddValueIntent(amount: -7).perform()
        XCTAssertEqual(b.value, 93)
        storedA = try await IntentFeatureA.FeatureAStore.shared.value()
        storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(storedA, 13)
        XCTAssertEqual(storedB, 93)
    }

    @MainActor
    func testCancellationBeforeAdmissionAndDuringDelayKeepsOldValues() async throws {
        let task = Task<Void, Error> { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await FeatureAAddValueIntent(amount: 8).perform()
        }
        do { _ = try await task.value; XCTFail("Cancellation was treated as success") }
        catch is CancellationError { }
        let storedA = try await IntentFeatureA.FeatureAStore.shared.value()
        let storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(storedA, 0)
        XCTAssertEqual(storedB, 0)

        _ = try await FeatureAAddValueIntent(amount: 4).perform()
        IntentFeatureA.FeatureAStore.shared.delayNextSave(nanoseconds: 5_000_000_000)
        let delayed = Task<Void, Error> { @MainActor in
            _ = try await FeatureAAddValueIntent(amount: 8).perform()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        delayed.cancel()
        do { _ = try await delayed.value; XCTFail("Delayed cancellation committed") }
        catch is CancellationError { }
        let afterDelayedCancellation = try await IntentFeatureA.FeatureAStore.shared.value()
        XCTAssertEqual(afterDelayedCancellation, 4)
    }

    @MainActor
    func testDelayedSaveRetainsOwnerReservationUntilCancellationDrains() async throws {
        let entered = expectation(description: "owned save admitted")
        let store = IntentFeatureA.FeatureAStore.shared
        store.configure(boundary: ObservedBoundary(entered: entered))
        store.delayNextSave(nanoseconds: 60_000_000_000)
        let task = Task { try await store.add(7) }
        await fulfillment(of: [entered], timeout: 5)
        do {
            try await MiniAppRestoreCoordinator.shared.withStoreMaintenance(for: .intentFixtureA) { }
            XCTFail("Exclusive maintenance raced a pending ordinary save")
        } catch let error as MiniAppRestoreCoordinator.Conflict {
            XCTAssertEqual(error.owners, [.intentFixtureA])
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled save committed") }
        catch is CancellationError { }
        store.configure(boundary: FeatureABoundary())
        try await MiniAppRestoreCoordinator.shared.withStoreMaintenance(for: .intentFixtureA) { }
        let value = try await store.value()
        XCTAssertEqual(value, 0)
    }

    @MainActor
    func testSaveFailureKeepsPreviousValueAndOtherOwner() async throws {
        _ = try await FeatureAAddValueIntent(amount: 4).perform()
        _ = try await FeatureBAddValueIntent(amount: 9).perform()
        IntentFeatureA.FeatureAStore.shared.injectNextSaveFailure()
        do { _ = try await FeatureAAddValueIntent(amount: 3).perform(); XCTFail("Save failure was treated as success") }
        catch IntentFeatureA.FeatureAStore.Failure.injectedSaveFailure { }
        let storedA = try await IntentFeatureA.FeatureAStore.shared.value()
        let storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        let retried = try await FeatureAAddValueIntent(amount: 2).perform()
        XCTAssertEqual(storedA, 4)
        XCTAssertEqual(storedB, 9)
        XCTAssertEqual(retried.value, 6)

        do { _ = try await FeatureAAddValueIntent(amount: .max).perform(); XCTFail("Overflow succeeded") }
        catch IntentFeatureA.FeatureAStore.Failure.valueOutOfRange { }
    }

    @MainActor
    func testDisableAndRemovalRejectAWhileBRemainsUsable() async throws {
        _ = try await FeatureAAddValueIntent(amount: 5).perform()
        _ = try await FeatureBAddValueIntent(amount: 20).perform()
        try await IntentFeatureA.FeatureAStore.shared.replaceEntries(["a": "A candidate"])
        try await IntentFeatureB.FeatureBStore.shared.replaceEntries(["b": "B candidate"])
        try await IntentFixtureIntegration.management.disable(.intentFixtureA)
        IntentFixtureIntegration.reconstructManagement()
        do { _ = try await FeatureAAddValueIntent(amount: 1).perform(); XCTFail("Disabled owner wrote") }
        catch let error as MiniAppRestoreCoordinator.Unavailable {
            XCTAssertEqual(error.owners, [.intentFixtureA])
        }
        do { _ = try await IntentFeatureA.EntryQuery().suggestedEntities(); XCTFail("Disabled owner returned suggestions") }
        catch let error as MiniAppRestoreCoordinator.Unavailable { XCTAssertEqual(error.owners, [.intentFixtureA]) }
        do { _ = try await IntentFeatureA.EntryQuery().entities(for: ["a"]); XCTFail("Disabled owner resolved an entity") }
        catch is MiniAppRestoreCoordinator.Unavailable { }
        let updatedB = try await FeatureBAddValueIntent(amount: 2).perform()
        let bSuggestions = try await IntentFeatureB.EntryQuery().suggestedEntities()
        XCTAssertEqual(updatedB.value, 22)
        XCTAssertEqual(bSuggestions.map(\.title), ["B candidate"])

        try await IntentFixtureIntegration.management.enable(.intentFixtureA)
        try await IntentFixtureIntegration.management.remove(.intentFixtureA)
        IntentFixtureIntegration.reconstructManagement()
        do { _ = try await FeatureAAddValueIntent(amount: 1).perform(); XCTFail("Removed owner wrote") }
        catch is MiniAppRestoreCoordinator.Unavailable { }
        let storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(storedB, 22)

        try await IntentFixtureIntegration.management.enable(.intentFixtureA)
        let emptyAValue = try await IntentFeatureA.FeatureAStore.shared.value()
        let emptyASuggestions = try await IntentFeatureA.EntryQuery().suggestedEntities()
        let retainedBSuggestions = try await IntentFeatureB.EntryQuery().suggestedEntities()
        XCTAssertEqual(emptyAValue, 0)
        XCTAssertTrue(emptyASuggestions.isEmpty)
        XCTAssertEqual(retainedBSuggestions.map(\.title), ["B candidate"])
        let retainedBValue = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(retainedBValue, 22)
    }

    @MainActor
    func testPersistentValuesSurviveManagementReconstruction() async throws {
        _ = try await FeatureAAddValueIntent(amount: 12).perform()
        _ = try await FeatureBAddValueIntent(amount: 34).perform()
        IntentFixtureIntegration.reconstructManagement()
        let storedA = try await IntentFeatureA.FeatureAStore.shared.value()
        let storedB = try await IntentFeatureB.FeatureBStore.shared.value()
        XCTAssertEqual(storedA, 12)
        XCTAssertEqual(storedB, 34)
    }
}

private struct ObservedBoundary: IntentFeatureA.StoreOperationBoundary {
    let entered: XCTestExpectation
    func perform<Value: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .intentFixtureA) {
            entered.fulfill()
            return try await operation()
        }
    }
}
