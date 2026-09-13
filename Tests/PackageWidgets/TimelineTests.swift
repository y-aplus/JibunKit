import Foundation
import JibunKitCore
import WidgetFeatureA
import WidgetFeatureB
import WidgetKit
import XCTest

final class TimelineTests: XCTestCase {
    func testPackageTimelinesRemainOwnerScoped() {
        let suite = "com.jibunkit.fixture.widget-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let aStore = FeatureAStore(defaults: defaults)
        let bStore = FeatureBStore(defaults: defaults)
        aStore.set(11)
        bStore.set(22)
        let aProvider = FeatureAProvider(store: aStore)
        let bProvider = FeatureBProvider(store: bStore)
        let a = aProvider.timeline()
        let b = bProvider.timeline()
        XCTAssertEqual(FeatureAWidget.kind, "com.jibunkit.fixture.feature-a.widget")
        XCTAssertEqual(FeatureBWidget.kind, "com.jibunkit.fixture.feature-b.widget")
        XCTAssertNotEqual(FeatureAWidget.kind, FeatureBWidget.kind)
        XCTAssertEqual(FeatureAWidget.supportedLocalizations, ["en", "ja"])
        XCTAssertEqual(FeatureBWidget.supportedLocalizations, ["en", "ja"])
        XCTAssertNotEqual(FeatureAWidget.displayName, "widget.name")
        XCTAssertNotEqual(FeatureBWidget.widgetDescription, "widget.description")
        XCTAssertEqual(a.entries.map(\.owner), ["owner-a"])
        XCTAssertEqual(b.entries.map(\.owner), ["owner-b"])
        XCTAssertEqual(a.entries.map(\.storageKey), ["owner-a.shared-value"])
        XCTAssertEqual(b.entries.map(\.storageKey), ["owner-b.shared-value"])
        XCTAssertEqual(a.entries.map(\.value), [11])
        XCTAssertEqual(b.entries.map(\.value), [22])
        XCTAssertEqual(FeatureAStore.localKey, FeatureBStore.localKey)

        aStore.set(33)
        XCTAssertEqual(aProvider.timeline().entries.map(\.value), [33])
        XCTAssertEqual(bProvider.timeline().entries.map(\.value), [22])
    }

    @MainActor
    func testNormalDefinitionsAndManagementKeepOtherWidgetWhileAChangesLifecycle() async throws {
        let suite = "com.jibunkit.fixture.widget-management-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let aStore = FeatureAStore(defaults: defaults)
        let bStore = FeatureBStore(defaults: defaults)
        aStore.set(11)
        bStore.set(22)
        let aLifetime = MiniAppFeatureLifetime(id: FeatureAStore.id)
        let bLifetime = MiniAppFeatureLifetime(id: FeatureBStore.id)
        let coordinator = MiniAppRestoreCoordinator()
        let management = MiniAppManagement(
            registrations: [
                .init(
                    id: FeatureAStore.id,
                    lifetime: aLifetime,
                    removal: .init(id: FeatureAStore.id, dataDescription: "A") { aStore.remove() }
                ),
                .init(
                    id: FeatureBStore.id,
                    lifetime: bLifetime,
                    removal: .init(id: FeatureBStore.id, dataDescription: "B") { bStore.remove() }
                ),
            ],
            defaults: defaults,
            consents: .init(defaults: defaults),
            coordinator: coordinator
        )
        XCTAssertEqual(FeatureAMiniApp.definition.id, FeatureAStore.id)
        XCTAssertEqual(FeatureBMiniApp.definition.id, FeatureBStore.id)
        XCTAssertEqual(FeatureAMiniApp.definition.lifetime?.id, FeatureAStore.id)
        XCTAssertEqual(FeatureBMiniApp.definition.removal?.id, FeatureBStore.id)

        aStore.set(33)
        XCTAssertEqual(FeatureAProvider(store: aStore).timeline().entries.map(\.value), [33])
        XCTAssertEqual(FeatureBProvider(store: bStore).timeline().entries.map(\.value), [22])

        try await management.disable(FeatureAStore.id)
        var a = FeatureAProvider(store: aStore).timeline().entries[0]
        var b = FeatureBProvider(store: bStore).timeline().entries[0]
        XCTAssertFalse(a.isEnabled)
        XCTAssertEqual(a.value, 0)
        XCTAssertTrue(b.isEnabled)
        XCTAssertEqual(b.value, 22)
        do {
            try await coordinator.withStoreAccess(for: FeatureAStore.id) { aStore.set(99) }
            XCTFail("Disabled A accepted a normal write")
        } catch is MiniAppRestoreCoordinator.Unavailable {}

        try await management.enable(FeatureAStore.id)
        XCTAssertEqual(FeatureAProvider(store: aStore).timeline().entries.map(\.value), [33])
        try await management.remove(FeatureAStore.id)
        a = FeatureAProvider(store: aStore).timeline().entries[0]
        b = FeatureBProvider(store: bStore).timeline().entries[0]
        XCTAssertFalse(a.isEnabled)
        XCTAssertEqual(b.value, 22)
        XCTAssertEqual(bStore.value(), 22)

        try await management.enable(FeatureAStore.id)
        try await coordinator.withStoreAccess(for: FeatureAStore.id) { aStore.set(44) }
        XCTAssertEqual(FeatureAProvider(store: aStore).timeline().entries.map(\.value), [44])
        XCTAssertEqual(FeatureBProvider(store: bStore).timeline().entries.map(\.value), [22])
    }
}
