import XCTest
import JibunKitCore

final class MiniAppWindowSceneRegistryTests: XCTestCase, @unchecked Sendable {
    private let a = MiniAppID("scene-a")
    private let b = MiniAppID("scene-b")

    @MainActor
    func testTwoWindowsKeepIndependentRoutesSelectionAndFeatureState() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let firstID = MiniAppWindowSessionID("persistent-one")
        let secondID = MiniAppWindowSessionID("persistent-two")
        var firstRoutes: [String?] = []
        var secondRoutes: [String?] = []
        var firstFeatureState = 11
        var secondFeatureState = 27
        let first = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) {
            firstRoutes.append($0?.destination)
        }
        let second = await registry.connect(sessionID: secondID, phase: .inactive, selectedID: b) {
            secondRoutes.append($0?.destination)
        }

        XCTAssertEqual(registry.open(try route(a, "detail-a"), in: firstID), .delivered(first))
        XCTAssertEqual(registry.open(try route(b, "detail-b"), in: secondID), .delivered(second))
        XCTAssertTrue(registry.update(first, phase: .inactive, selectedID: b))
        firstFeatureState += 1

        XCTAssertEqual(firstRoutes, ["detail-a"])
        XCTAssertEqual(secondRoutes, ["detail-b"])
        XCTAssertEqual(firstFeatureState, 12)
        XCTAssertEqual(secondFeatureState, 27)
        XCTAssertEqual(registry.snapshot(for: firstID)?.selectedID, b)
        XCTAssertEqual(registry.snapshot(for: secondID)?.selectedID, b)
    }

    @MainActor
    func testDisconnectReleasesOnlyThatWindowAndDoesNotStopGlobalOwner() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let runtime = MiniAppRuntime()
        var globalStopped = false
        try runtime.onShutdown { globalStopped = true }
        var releases: [String] = []
        let firstID = MiniAppWindowSessionID("one")
        let secondID = MiniAppWindowSessionID("two")
        let first = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) { _ in }
        let second = await registry.connect(sessionID: secondID, phase: .active, selectedID: a) { _ in }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: first) { releases.append("one-a") })
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: first) { releases.append("one-b") })
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: second) { releases.append("two-a") })

        let disconnected = await registry.disconnect(first)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(Set(releases), ["one-a", "one-b"])
        XCTAssertNotNil(registry.snapshot(for: secondID))
        XCTAssertFalse(globalStopped)
        XCTAssertFalse(runtime.isClosed)
        XCTAssertEqual(registry.open(nil, in: secondID), .delivered(second))
        await runtime.shutdown()
        XCTAssertTrue(globalStopped)
    }

    @MainActor
    func testRestoreKeepsSessionIdentityButRejectsOldGenerationAndLateDisconnect() async {
        let registry = MiniAppWindowSceneRegistry()
        let sessionID = MiniAppWindowSessionID("restored")
        var oldDeliveries = 0
        var newDeliveries = 0
        var oldReleased = false
        let old = await registry.connect(sessionID: sessionID, phase: .background, selectedID: a) { _ in
            oldDeliveries += 1
        }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: old) { oldReleased = true })
        let restored = await registry.connect(sessionID: sessionID, phase: .inactive, selectedID: b) { _ in
            newDeliveries += 1
        }

        XCTAssertTrue(oldReleased)
        XCTAssertEqual(restored.sessionID, old.sessionID)
        XCTAssertNotEqual(restored.generation, old.generation)
        XCTAssertEqual(
            registry.open(nil, in: sessionID, expected: old),
            .staleConnection(current: restored)
        )
        let staleDisconnected = await registry.disconnect(old)
        XCTAssertFalse(staleDisconnected)
        XCTAssertEqual(registry.open(nil, in: sessionID, expected: restored), .delivered(restored))
        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(newDeliveries, 1)
    }

    @MainActor
    func testCleanupIsReverseRegistrationOrderWithinOwner() async {
        let registry = MiniAppWindowSceneRegistry()
        let id = MiniAppWindowSessionID("cleanup")
        let connection = await registry.connect(sessionID: id, phase: .active, selectedID: a) { _ in }
        var releases: [Int] = []
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) { releases.append(1) })
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) { releases.append(2) })
        let disconnected = await registry.disconnect(connection)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(releases, [2, 1])
    }

    private func route(_ id: MiniAppID, _ destination: String) throws -> MiniAppRoute {
        let url = try XCTUnwrap(MiniAppLink.url(for: id, destination: destination))
        return try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
    }
}
