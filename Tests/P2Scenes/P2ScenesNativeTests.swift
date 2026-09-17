#if os(iOS)
import XCTest
import UIKit
import JibunKitCore

final class P2ScenesNativeTests: XCTestCase, @unchecked Sendable {
    /// This test intentionally requires two OS UIWindowScene objects. A pair of
    /// Swift model instances is not accepted as evidence of multiwindow success.
    @MainActor
    func testIPadHostHasTwoDistinctOSWindowSessionsForManualScenario() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("The two-window diagnostic is iPad-only")
        }
        let sessions = P2ScenesOSDiagnostic.connectedWindowSessions
        guard sessions.count >= 2 else {
            throw XCTSkip("Open a second window through the iPad multitasking UI before running this diagnostic")
        }
        XCTAssertGreaterThanOrEqual(Set(sessions).count, 2)
    }

    @MainActor
    func testTwoConnectionsRouteBySessionAndOldGenerationCannotAffectRestoredWindow() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let a = MiniAppID("p2-scene-a")
        let b = MiniAppID("p2-scene-b")
        let firstID = MiniAppWindowSessionID("native-a")
        let secondID = MiniAppWindowSessionID("native-b")
        var first: [MiniAppID] = []
        var second: [MiniAppID] = []
        let old = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) {
            if let id = $0?.id { first.append(id) }
        }
        let other = await registry.connect(sessionID: secondID, phase: .active, selectedID: b) {
            if let id = $0?.id { second.append(id) }
        }
        _ = registry.open(try route(a), in: firstID, expected: old)
        _ = registry.open(try route(b), in: secondID, expected: other)
        let restored = await registry.connect(sessionID: firstID, phase: .inactive, selectedID: a) { _ in }

        XCTAssertEqual(registry.open(nil, in: firstID, expected: old), .staleConnection(current: restored))
        XCTAssertEqual(first, [a])
        XCTAssertEqual(second, [b])
        XCTAssertEqual(registry.snapshot(for: secondID)?.connection, other)
    }

    private func route(_ id: MiniAppID) throws -> MiniAppRoute {
        let url = try XCTUnwrap(MiniAppLink.url(for: id))
        return try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
    }
}
#endif
