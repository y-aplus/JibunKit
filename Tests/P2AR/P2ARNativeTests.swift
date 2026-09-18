#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import AVFoundation
import XCTest
import JibunKitCore

@MainActor
final class P2ARNativeTests: XCTestCase, @unchecked Sendable {
    func testProbeUsesNormalDefinitionLifetimePermissionAndFeatureDelegate() {
        let definition = P2ARProbe.definitions[0]
        XCTAssertEqual(definition.id, MiniAppID("p2-ar"))
        XCTAssertNotNil(definition.lifetime)
        XCTAssertNotNil(definition.onSceneActivityChange)
        XCTAssertEqual(definition.permissions.map(\.id), ["camera"])
        XCTAssertTrue(P2ARProbe.feature.session.delegate === P2ARProbe.feature.delegate)
    }

#if targetEnvironment(simulator)
    func testSimulatorReportsUnsupportedAndDoesNotClaimTracking() async throws {
        XCTAssertFalse(ARWorldTrackingConfiguration.isSupported)
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-simulator"), coordinator: .init(),
            permissions: P2ARAllowedPermission()
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let sceneID = UUID()
        feature.owner.receive(.init(
            featureID: feature.id, sceneID: sceneID, phase: .active, isSelected: true
        ))
        await feature.start(in: sceneID)
        XCTAssertTrue(feature.state.status.contains("unsupported"))
        XCTAssertEqual(feature.state.frameCount, 0)
        await feature.lifetime.stop()
    }
#else
    func testPhysicalDeviceProducesRealTrackingFrameAndStops() async throws {
        XCTAssertTrue(ARWorldTrackingConfiguration.isSupported, "Run on an ARKit-capable device")
        XCTAssertEqual(
            AVCaptureDevice.authorizationStatus(for: .video), .authorized,
            "Grant camera permission through the normal Feature UI before device evidence"
        )
        let feature = P2ARFeature(id: MiniAppID("p2-ar-device"), coordinator: .init())
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let sceneID = UUID()
        feature.owner.receive(.init(
            featureID: feature.id, sceneID: sceneID, phase: .active, isSelected: true
        ))
        await feature.start(in: sceneID)
        for _ in 0..<100 {
            if feature.state.frameCount > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(feature.state.frameCount, 0, "No real ARFrame was observed")
        await feature.stop()
        XCTAssertEqual(feature.state.status, "AR停止・camera解放")
        await feature.lifetime.stop()
    }
#endif

    private func allowedStore(owner: MiniAppID) throws -> MiniAppConsentStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "P2AR.\(UUID().uuidString)"))
        let store = MiniAppConsentStore(defaults: defaults)
        store.setConsent(.allowed, for: owner, permissionID: "camera")
        return store
    }
}

@MainActor
private final class P2ARAllowedPermission: MiniAppCapturePermissionClient {
    func request(_ resource: MiniAppCaptureResource) async -> Bool { true }
}
#endif
