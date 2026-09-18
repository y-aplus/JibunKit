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

    func testDiagnosticUUIDValidationAcceptsBLEFormsAndRejectsMalformedInput() {
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID(" 180d "), "180D")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("12345678"), "12345678")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("00112233445566778899aabbccddeeff"),
                       "00112233445566778899AABBCCDDEEFF")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("00112233-4455-6677-8899-aabbccddeeff"),
                       "00112233-4455-6677-8899-AABBCCDDEEFF")
        XCTAssertNil(P2BluetoothDiagnosticInput.normalizedUUID("180"))
        XCTAssertNil(P2BluetoothDiagnosticInput.normalizedUUID("ZZZZ"))
    }

    func testDiagnosticHexValidationIsLosslessAndRejectsBeforeNativeUse() {
        XCTAssertEqual(P2BluetoothDiagnosticInput.data(hex: "00 ff 10"), Data([0, 255, 16]))
        XCTAssertEqual(P2BluetoothDiagnosticInput.hex(Data([0, 255, 16])), "00 FF 10")
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: ""))
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: "0"))
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: "GG"))
    }

    func testDiagnosticStateShowsDiscoveryReadWriteAndNotifyCallbacks() async throws {
        let suite = "P2BluetoothDiagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults), pool = P2BluetoothNativeFakePool()
        let feature = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-diagnostic"), title: "Diagnostic",
            coordinator: MiniAppBluetoothCoordinator(factory: pool.make), consents: store)
        store.setConsent(.allowed, for: feature.id, permissionID: "bluetooth")
        try await feature.lifetime.start()
        let peripheral = UUID(); feature.connect(.init(id: peripheral))
        for _ in 0..<20 where feature.connection == nil { await Task.yield() }
        let connection = try XCTUnwrap(feature.connection)
        let native = try XCTUnwrap(pool.centrals.first)
        let key = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        feature.serviceUUID = "invalid"; feature.read()
        feature.serviceUUID = "180D"; feature.writeHex = "GG"; feature.write()
        XCTAssertEqual(native.readCalls, 0); XCTAssertEqual(native.writeCalls, 0)
        feature.writeHex = "01"
        native.emit(.services(peripheral: connection.peripheral, generation: connection.generation, identifiers: ["180D", "180F"]))
        native.emit(.characteristics(peripheral: connection.peripheral, generation: connection.generation,
                                     service: "180D", identifiers: ["2A37", "2A38"]))
        feature.read()
        native.emit(.value(peripheral: connection.peripheral, generation: connection.generation,
                           characteristic: key, data: Data([1, 2]), notifying: false))
        native.emit(.value(peripheral: connection.peripheral, generation: connection.generation,
                           characteristic: key, data: Data([0, 255]), notifying: true))
        native.emit(.writeCompleted(peripheral: connection.peripheral, generation: connection.generation, characteristic: key))
        native.emit(.notificationChanged(peripheral: connection.peripheral, generation: connection.generation,
                                         characteristic: key, enabled: true))
        XCTAssertEqual(feature.discoveredServices, ["180D", "180F"])
        XCTAssertEqual(feature.discoveredCharacteristics, ["2A37", "2A38"])
        XCTAssertEqual(feature.lastReadHex, "2A37: 01 02")
        XCTAssertEqual(feature.lastNotifyHex, "2A37: 00 FF")
        XCTAssertEqual(feature.writeResult, "成功: 2A37")
        XCTAssertEqual(feature.notifyResult, "2A37: 購読中")
        await feature.lifetime.stop(); await feature.service.unregisterAllOwned()
    }

    func testRestoredConnectedEventRecoversOperationalConnectionTicket() async throws {
        let suite = "P2BluetoothRestoredDiagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults), pool = P2BluetoothNativeFakePool()
        let feature = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-restored-ui"), title: "Restored",
            coordinator: MiniAppBluetoothCoordinator(factory: pool.make), consents: store)
        store.setConsent(.allowed, for: feature.id, permissionID: "bluetooth")
        try feature.definition.onHostLaunch?()
        let native = try XCTUnwrap(pool.centrals.first)
        let peripheral = UUID(), generation = UUID()
        native.emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        for _ in 0..<20 where feature.lifetime.state != .running { await Task.yield() }
        let connection = try XCTUnwrap(feature.connection)
        XCTAssertEqual(connection.peripheral, peripheral)
        XCTAssertEqual(connection.generation, generation)
        XCTAssertEqual(feature.status, "復元接続済み（診断操作可能）")
        await feature.lifetime.stop(); await feature.service.unregisterAllOwned()
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
    var centrals: [P2BluetoothNativeFakeCentral] = []
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { [self] _, _ in
        let central = P2BluetoothNativeFakeCentral(); self.centrals.append(central); return central
    }
}

@MainActor private final class P2BluetoothNativeFakeCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn
    var authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    var readCalls = 0, writeCalls = 0
    func emit(_ event: MiniAppBluetoothEvent) { eventHandler?(event) }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    func stopScan() {}
    func connect(peripheral: UUID, generation: UUID) {}
    func disconnect(peripheral: UUID, generation: UUID) async {}
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) { readCalls += 1 }
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
               peripheral: UUID, generation: UUID) throws { writeCalls += 1 }
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func stopAll() async {}
}
#endif
