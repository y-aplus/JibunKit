#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppARSessionAdapterTests: XCTestCase {
    func testAdapterKeepsFeatureDelegateAndRejectsUnsupportedBeforeRunning() async throws {
        let session = ARSession()
        let delegate = FeatureARDelegate()
        session.delegate = delegate
        let bridge = MiniAppARSessionEventBridge()
        let adapter = MiniAppARSessionAdapter(
            session: session,
            configuration: ARWorldTrackingConfiguration(),
            runOptions: [.resetTracking],
            restartOptions: [],
            eventBridge: bridge,
            isSupported: { false }
        )
        XCTAssertTrue(session.delegate === delegate)

        let permissions = ARPermissions()
        let owner = MiniAppCaptureOwner(
            id: MiniAppID("ar-unsupported"), coordinator: .init(),
            permissions: permissions, consent: { _ in true }
        )
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let sceneID = UUID()
        owner.receive(.init(featureID: owner.id, sceneID: sceneID, phase: .active, isSelected: true))
        await XCTAssertThrowsErrorAsync(try await owner.start(
            try adapter.operation(), sceneScope: .scene(sceneID)
        )) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .unsupported)
        }
        XCTAssertTrue(permissions.requested.isEmpty)
        XCTAssertNil(session.currentFrame)
    }

    func testFeatureForwardedEventsUseOneGenerationAndFinishOnEnd() async throws {
        let bridge = MiniAppARSessionEventBridge()
        let events = try bridge.begin()
        var iterator = events.stream.makeAsyncIterator()
        bridge.interruptionBegan(reason: "camera unavailable")
        let interrupted = await iterator.next()
        bridge.interruptionEnded()
        let resumed = await iterator.next()
        bridge.runtimeFailed(reason: "reset", canRestart: true)
        let failed = await iterator.next()
        bridge.end()
        let ended = await iterator.next()

        XCTAssertEqual(interrupted, .interrupted(generation: events.generation, reason: "camera unavailable"))
        XCTAssertEqual(resumed, .interruptionEnded(generation: events.generation))
        XCTAssertEqual(failed, .runtimeFailed(generation: events.generation, reason: "reset", canRestart: true))
        XCTAssertNil(ended)
    }
}

private final class FeatureARDelegate: NSObject, ARSessionDelegate {}

@MainActor
private final class ARPermissions: MiniAppCapturePermissionClient {
    private(set) var requested: [MiniAppCaptureResource] = []
    func request(_ resource: MiniAppCaptureResource) async -> Bool {
        requested.append(resource)
        return true
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do { _ = try await expression(); XCTFail("expected error") }
    catch { handler(error) }
}
#endif
