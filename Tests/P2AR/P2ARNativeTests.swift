#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import XCTest
import JibunKitCore
@testable import JibunKit_App

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

    func testSimulatorReportsUnsupportedAndDoesNotClaimTracking() async throws {
        XCTAssertFalse(ARWorldTrackingConfiguration.isSupported)
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-simulator"), coordinator: .init(),
            permissions: P2ARAllowedPermission()
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.owner.receive($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        await feature.start(in: sceneID)
        XCTAssertTrue(feature.state.status.contains("unsupported"))
        XCTAssertEqual(feature.state.frameCount, 0)
        await feature.lifetime.stop()
    }

    func testConsentRevocationStopsOwnedOperationAndUpdatesStatus() async throws {
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-consent"), coordinator: .init(),
            permissions: P2ARAllowedPermission()
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.owner.receive($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        try await feature.owner.start(
            .init(resources: [.camera]) { { _ in } }, sceneScope: .scene(sceneID)
        )
        XCTAssertEqual(feature.state.status, "AR実行中")

        try feature.definition.setConsent(.denied, permissionID: "camera", in: store)
        await eventually { feature.owner.state == .suspended(.featureStopped) }
        XCTAssertTrue(feature.state.status.contains("AR中断/停止"))
        await feature.lifetime.stop()
    }

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

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("condition was not reached")
}
#endif
