import Foundation
import JibunKitCore
import WidgetFeatureA
import WidgetFeatureB
import WidgetKit
import XCTest

final class TimelineTests: XCTestCase, @unchecked Sendable {
    func testPackageTimelinesRemainOwnerScopedAndLocalized() throws {
        let suite = "com.jibunkit.fixture.widget-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let aStore = FeatureAStore(defaults: defaults)
        let bStore = FeatureBStore(defaults: defaults)
        try aStore.set(11)
        try bStore.set(22)
        let aProvider = FeatureAProvider(store: aStore)
        let bProvider = FeatureBProvider(store: bStore)
        let a = aProvider.timeline().entries[0]
        let b = bProvider.timeline().entries[0]

        XCTAssertEqual(FeatureAWidget.kind, "com.jibunkit.fixture.feature-a.widget")
        XCTAssertEqual(FeatureBWidget.kind, "com.jibunkit.fixture.feature-b.widget")
        XCTAssertNotEqual(FeatureAWidget.kind, FeatureBWidget.kind)
        XCTAssertEqual(FeatureAWidget.supportedLocalizations, ["en", "ja"])
        XCTAssertEqual(FeatureBWidget.supportedLocalizations, ["en", "ja"])
        XCTAssertNotEqual(FeatureAWidget.displayName, "widget.name")
        XCTAssertNotEqual(FeatureBWidget.widgetDescription, "widget.description")
        XCTAssertEqual(a.owner, "owner-a")
        XCTAssertEqual(b.owner, "owner-b")
        XCTAssertEqual(a.storageKey, "owner-a.shared-value")
        XCTAssertEqual(b.storageKey, "owner-b.shared-value")
        XCTAssertEqual(a.value, 11)
        XCTAssertEqual(b.value, 22)
        XCTAssertEqual(FeatureAStore.localKey, FeatureBStore.localKey)

        try aStore.set(33)
        XCTAssertEqual(aProvider.timeline().entries[0].value, 33)
        XCTAssertEqual(bProvider.timeline().entries[0].value, 22)
    }

    func testMissingSharedStoreIsUnavailableInsteadOfFallingBackToStandardDefaults() {
        let a = FeatureAProvider().timeline().entries[0]
        let b = FeatureBProvider().timeline().entries[0]
        XCTAssertFalse(a.storeAvailable)
        XCTAssertFalse(b.storeAvailable)
        XCTAssertNil(a.value)
        XCTAssertNil(b.value)
    }

    @MainActor
    func testActualDefinitionsPreserveColdLaunchStateAndDeleteOnlyA() async throws {
        let suite = "com.jibunkit.fixture.widget-management-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let aStore = FeatureAStore(defaults: defaults)
        let bStore = FeatureBStore(defaults: defaults)

        var assembly = makeAssembly(defaults: defaults, aStore: aStore, bStore: bStore)
        try await seedMissingEnabledOwners(assembly, aStore: aStore, bStore: bStore)
        XCTAssertEqual(try aStore.value(), 11, "First launch seeds missing A")
        XCTAssertEqual(try bStore.value(), 22, "First launch seeds missing B")

        try await FeatureAAccess(store: aStore, coordinator: assembly.coordinator).set(33)
        assembly = makeAssembly(defaults: defaults, aStore: aStore, bStore: bStore)
        try await seedMissingEnabledOwners(assembly, aStore: aStore, bStore: bStore)
        XCTAssertEqual(try aStore.value(), 33, "Cold reconstruction must not overwrite updated A")
        XCTAssertEqual(try bStore.value(), 22)

        try await assembly.management.disable(FeatureAStore.id)
        assembly = makeAssembly(defaults: defaults, aStore: aStore, bStore: bStore)
        try await seedMissingEnabledOwners(assembly, aStore: aStore, bStore: bStore)
        XCTAssertEqual(assembly.management.status(for: FeatureAStore.id), .disabled)
        XCTAssertEqual(try aStore.value(), 33, "Disabled cold launch retains A without reseeding")
        XCTAssertEqual(try bStore.value(), 22, "Disabled A must not stop B initialization")
        XCTAssertNil(FeatureAProvider(store: aStore).timeline().entries[0].value)
        XCTAssertEqual(FeatureBProvider(store: bStore).timeline().entries[0].value, 22)
        do {
            try await FeatureAAccess(store: aStore, coordinator: assembly.coordinator).set(99)
            XCTFail("Disabled A accepted a coordinated write")
        } catch is MiniAppRestoreCoordinator.Unavailable {}

        try await assembly.management.enable(FeatureAStore.id)
        try await assembly.management.remove(FeatureAStore.id)
        XCTAssertNil(try aStore.value(), "Definition removal callback must delete A before any replacement write")
        XCTAssertEqual(try bStore.value(), 22)

        assembly = makeAssembly(defaults: defaults, aStore: aStore, bStore: bStore)
        try await seedMissingEnabledOwners(assembly, aStore: aStore, bStore: bStore)
        XCTAssertEqual(assembly.management.status(for: FeatureAStore.id), .removed)
        XCTAssertNil(try aStore.value(), "Removed cold launch must not recreate A")
        XCTAssertEqual(try bStore.value(), 22)

        try await assembly.management.enable(FeatureAStore.id)
        XCTAssertNil(try aStore.value(), "Re-enable restores admission but must leave deleted A empty")
        XCTAssertNil(FeatureAProvider(store: aStore).timeline().entries[0].value)
        try await FeatureAAccess(store: aStore, coordinator: assembly.coordinator).set(44)
        XCTAssertEqual(FeatureAProvider(store: aStore).timeline().entries[0].value, 44)
        XCTAssertEqual(FeatureBProvider(store: bStore).timeline().entries[0].value, 22)
    }

    @MainActor
    private func makeAssembly(
        defaults: UserDefaults, aStore: FeatureAStore, bStore: FeatureBStore
    ) -> Assembly {
        let coordinator = MiniAppRestoreCoordinator()
        let aLifetime = MiniAppFeatureLifetime(id: FeatureAStore.id)
        let bLifetime = MiniAppFeatureLifetime(id: FeatureBStore.id)
        let definitions = [
            FeatureAMiniApp.definition(store: aStore, lifetime: aLifetime, coordinator: coordinator),
            FeatureBMiniApp.definition(store: bStore, lifetime: bLifetime, coordinator: coordinator),
        ]
        XCTAssertEqual(definitions.map(\.id), [FeatureAStore.id, FeatureBStore.id])
        XCTAssertEqual(definitions.map { $0.lifetime?.id }, [FeatureAStore.id, FeatureBStore.id])
        XCTAssertEqual(definitions.map { $0.removal?.id }, [FeatureAStore.id, FeatureBStore.id])
        _ = definitions.map { $0.makeDestination() }
        let management = MiniAppManagement(
            registrations: definitions.map { definition in
                .init(id: definition.id, lifetime: definition.lifetime, removal: definition.removal,
                      unregister: { try await definition.onUnregister?() })
            }, defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        return Assembly(management: management, coordinator: coordinator)
    }

    @MainActor
    private func seedMissingEnabledOwners(
        _ assembly: Assembly, aStore: FeatureAStore, bStore: FeatureBStore
    ) async throws {
        if assembly.management.isEnabled(FeatureAStore.id) {
            try await assembly.coordinator.withStoreAccess(for: FeatureAStore.id) { try aStore.seedIfMissing(11) }
        }
        if assembly.management.isEnabled(FeatureBStore.id) {
            try await assembly.coordinator.withStoreAccess(for: FeatureBStore.id) { try bStore.seedIfMissing(22) }
        }
    }
}

@MainActor
private struct Assembly {
    let management: MiniAppManagement
    let coordinator: MiniAppRestoreCoordinator
}
