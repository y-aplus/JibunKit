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
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        await definitions[0].lifetime?.stop()
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(definitions[1].lifetime?.state, .running)
        await definitions[1].lifetime?.stop()
    }
    func testNativeAdapterUsesStableDistinctRestoreIdentifiers() {
        let a = MiniAppID("native-ble-a"), b = MiniAppID("native-ble-b")
        XCTAssertNotEqual(MiniAppBluetoothCoordinator.restorationIdentifier(for: a),
                          MiniAppBluetoothCoordinator.restorationIdentifier(for: b))
        _ = MiniAppCoreBluetoothCentral(owner: a,
            restorationIdentifier: MiniAppBluetoothCoordinator.restorationIdentifier(for: a))
    }
}
#endif
