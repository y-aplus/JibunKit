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

    func testSameSceneCameraContenderRejectsThenSwitchesWithoutImplicitARRestart() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let calls = P2ARContenderCalls()
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-contender-test"), coordinator: coordinator,
            permissions: P2ARAllowedPermission(),
            contenderOperation: {
                MiniAppCaptureOperation(resources: [.camera]) {
                    calls.contenderStarts += 1
                    return { _ in calls.contenderStops += 1 }
                }
            }
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.definition.onSceneActivityChange?($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        let arOperation = MiniAppCaptureOperation(resources: [.camera]) {
            calls.arStarts += 1
            return { _ in calls.arStops += 1 }
        }
        try await feature.owner.start(arOperation, sceneScope: .scene(sceneID))

        await feature.startContender(switching: .reject, in: sceneID)
        XCTAssertEqual(feature.owner.state, .running([.camera]))
        XCTAssertEqual(calls.contenderStarts, 0)

        await feature.startContender(switching: .stopCurrent, in: sceneID)
        XCTAssertEqual(feature.owner.state, .suspended(.switched(to: feature.contenderOwner.id)))
        XCTAssertEqual(feature.contenderOwner.state, .running([.camera]))
        XCTAssertEqual(calls.arStops, 1)
        XCTAssertEqual(calls.contenderStarts, 1)

        await feature.stopContender()
        XCTAssertEqual(feature.owner.state, .suspended(.switched(to: feature.contenderOwner.id)))
        XCTAssertEqual(calls.arStarts, 1, "Stopping B must not implicitly restart AR")
        XCTAssertEqual(calls.contenderStops, 1)
        try await feature.owner.start(arOperation, sceneScope: .scene(sceneID))
        XCTAssertEqual(feature.owner.state, .running([.camera]))
        XCTAssertEqual(calls.arStarts, 2)

        await feature.startContender(switching: .stopCurrent, in: sceneID)
        dispatcher.update(phase: .background, selectedID: feature.id)
        await eventually { feature.contenderOwner.state == .suspended(.background) }
        dispatcher.update(phase: .active, selectedID: feature.id)
        await feature.startContender(switching: .reject, in: sceneID)
        XCTAssertEqual(feature.contenderOwner.state, .running([.camera]))
        dispatcher.disconnect()
        await eventually { feature.contenderOwner.state == .suspended(.disconnected) }
        await feature.lifetime.stop()
    }

    func testArtificialObservationEventsAreTimestampedBoundedAndMarkRestartFrame() {
        let state = P2ARState()
        for index in 0..<85 { state.append("artificial test event \(index)") }
        XCTAssertEqual(state.observationLines.count, 80)
        XCTAssertTrue(state.observationLines.first?.contains("artificial test event 5") == true)

        state.osInterruptionBegan()
        state.osInterruptionEnded()
        state.observeARState(.running([.camera]))
        state.receivedFrame()

        XCTAssertTrue(state.observationLines.contains { $0.contains("OS ARSessionDelegate interruption began") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("AR restart completed after OS interruption") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("first frame after OS interruption") })
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
private final class P2ARContenderCalls {
    var arStarts = 0
    var arStops = 0
    var contenderStarts = 0
    var contenderStops = 0
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
