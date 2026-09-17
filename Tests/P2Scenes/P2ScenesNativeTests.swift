#if os(iOS)
import XCTest
import UIKit
import JibunKitCore

final class P2ScenesNativeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRequesterCreatesRoutesAndDestroysSecondOSWindowSession() async throws {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad, "P2Scenes native target must use an iPad destination")
        let original = Set(P2ScenesOSDiagnostic.connectedWindowSessions)
        XCTAssertFalse(original.isEmpty, "The native host must have a connected UIWindowScene")
        let requester = MiniAppUIKitWindowSceneRequester()
        var requestFailure: Error?
        requester.requestWindow(userActivity: nil) { requestFailure = $0 }
        let createdID = await waitForNewSession(excluding: original, failure: { requestFailure })
        guard let createdID else {
            XCTFail("UIKit did not connect a second window session: \(requestFailure.map(String.init(describing:)) ?? "no explicit error")")
            return
        }

        let registry = MiniAppWindowSceneRegistry()
        let a = MiniAppID("p2-scene-a")
        let b = MiniAppID("p2-scene-b")
        let firstID = MiniAppWindowSessionID(try XCTUnwrap(original.first))
        let secondID = MiniAppWindowSessionID(createdID)
        var first: [MiniAppID] = []
        var second: [MiniAppID] = []
        let firstConnection = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) {
            if let id = $0?.id { first.append(id) }
        }
        let secondConnection = await registry.connect(sessionID: secondID, phase: .active, selectedID: b) {
            if let id = $0?.id { second.append(id) }
        }
        XCTAssertEqual(registry.open(try route(a), in: firstID, expected: firstConnection), .delivered(firstConnection))
        XCTAssertEqual(registry.open(try route(b), in: secondID, expected: secondConnection), .delivered(secondConnection))
        XCTAssertEqual(first, [a])
        XCTAssertEqual(second, [b])

        var destroyFailure: Error?
        XCTAssertTrue(requester.destroyWindow(sessionID: secondID) { destroyFailure = $0 })
        let destroyed = await waitForSessionRemoval(createdID, failure: { destroyFailure })
        XCTAssertTrue(destroyed, "UIKit did not destroy the requested session: \(destroyFailure.map(String.init(describing:)) ?? "no explicit error")")
        let disconnected = await registry.disconnect(secondConnection)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(registry.snapshot(for: firstID)?.connection, firstConnection)
    }

    private func route(_ id: MiniAppID) throws -> MiniAppRoute {
        let url = try XCTUnwrap(MiniAppLink.url(for: id))
        return try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
    }

    @MainActor
    private func waitForNewSession(
        excluding original: Set<String>,
        failure: () -> Error?
    ) async -> String? {
        for _ in 0..<100 {
            if failure() != nil { return nil }
            if let created = Set(P2ScenesOSDiagnostic.connectedWindowSessions).subtracting(original).first {
                return created
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor
    private func waitForSessionRemoval(_ id: String, failure: () -> Error?) async -> Bool {
        for _ in 0..<100 {
            if failure() != nil { return false }
            if !P2ScenesOSDiagnostic.connectedWindowSessions.contains(id) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
#endif
