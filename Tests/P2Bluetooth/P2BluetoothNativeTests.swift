#if os(iOS)
import XCTest
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2BluetoothNativeTests: XCTestCase {
    func testProbePublishesTwoFeatureDefinitionsWithOwnedLifecycleAndLaunchHook() {
        let definitions = P2BluetoothProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-bluetooth-sensor"), MiniAppID("p2-bluetooth-accessory")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onHostLaunch != nil && $0.onUnregister != nil })
        XCTAssertEqual(definitions.flatMap(\.permissions).map(\.id), ["bluetooth", "bluetooth"])
    }
    func testFeatureLifetimesAreIndependent() async throws {
        let definitions = P2BluetoothProbe.definitions
        let store = MiniAppConsentStore(defaults: .standard)
        definitions.forEach { store.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
        defer { definitions.forEach { store.removeConsent(for: $0.id, permissionID: "bluetooth") } }
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        await definitions[0].lifetime?.stop()
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(definitions[1].lifetime?.state, .running)
        await definitions[1].lifetime?.stop()
    }
    func testNativeAdapterUsesStableDistinctRestoreIdentifiersWithoutConstructingManager() {
        let a = MiniAppID("native-ble-a"), b = MiniAppID("native-ble-b")
        XCTAssertNotEqual(MiniAppBluetoothCoordinator.restorationIdentifier(for: a),
                          MiniAppBluetoothCoordinator.restorationIdentifier(for: b))
    }

    func testManagementDisableStopsOnlySelectedFeature() async throws {
        let definitions = P2BluetoothProbe.definitions
        let featureConsents = MiniAppConsentStore(defaults: .standard)
        definitions.forEach { featureConsents.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
        defer { definitions.forEach { featureConsents.removeConsent(for: $0.id, permissionID: "bluetooth") } }
        let suite = "P2BluetoothManagement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let management = MiniAppManagement(registrations: definitions.map { definition in
            .init(id: definition.id, lifetime: definition.lifetime,
                  unregister: { try await definition.onUnregister?() })
        }, defaults: defaults, consents: MiniAppConsentStore(defaults: defaults))
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        P2BluetoothProbe.accessory.status = "B noninitial"
        try await management.disable(definitions[0].id)
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(P2BluetoothProbe.accessory.status, "B noninitial")
        await definitions[1].lifetime?.stop()
        await P2BluetoothProbe.accessory.service.unregisterAllOwned()
    }
}
#endif
