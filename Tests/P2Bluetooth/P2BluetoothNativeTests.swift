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
        let fixture = try makeFixture(), definitions = fixture.definitions, store = fixture.store
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        definitions.forEach { store.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
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
        let fixture = try makeFixture(), definitions = fixture.definitions, featureConsents = fixture.store
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        definitions.forEach { featureConsents.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
        let suite = "P2BluetoothManagement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let management = MiniAppManagement(registrations: definitions.map { definition in
            .init(id: definition.id, lifetime: definition.lifetime,
                  unregister: { try await definition.onUnregister?() })
        }, defaults: defaults, consents: MiniAppConsentStore(defaults: defaults))
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        fixture.features[1].status = "B noninitial"
        try await management.disable(definitions[0].id)
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(fixture.features[1].status, "B noninitial")
        await definitions[1].lifetime?.stop()
        await fixture.features[1].service.unregisterAllOwned()
    }

    private func makeFixture() throws -> (features: [P2BluetoothFeature], definitions: [MiniAppDefinition],
                                           store: MiniAppConsentStore, defaults: UserDefaults, suite: String) {
        let suite = "P2BluetoothFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = MiniAppConsentStore(defaults: defaults)
        let pool = P2BluetoothNativeFakePool()
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let features = [
            P2BluetoothFeature(id: MiniAppID("p2-bluetooth-sensor"), title: "BLE Sensor", coordinator: coordinator, consents: store),
            P2BluetoothFeature(id: MiniAppID("p2-bluetooth-accessory"), title: "BLE Accessory", coordinator: coordinator, consents: store),
        ]
        return (features, features.map(\.definition), store, defaults, suite)
    }
}

@MainActor private final class P2BluetoothNativeFakePool {
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { _, _ in P2BluetoothNativeFakeCentral() }
}

@MainActor private final class P2BluetoothNativeFakeCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn
    var authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    func stopScan() {}
    func connect(peripheral: UUID, generation: UUID) {}
    func disconnect(peripheral: UUID, generation: UUID) async {}
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
               peripheral: UUID, generation: UUID) throws {}
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func stopAll() async {}
}
#endif
