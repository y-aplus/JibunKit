import Foundation
import XCTest
import JibunKitCore

final class MiniAppSceneRouterTests: XCTestCase {
    private func route(_ id: MiniAppID) throws -> MiniAppRoute {
        let url = try XCTUnwrap(MiniAppLink.url(for: id))
        return try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
    }

    @MainActor
    func testOnlySelectedSceneReceivesRoutesAcrossActivationAndRemoval() throws {
        let router = MiniAppSceneRouter()
        let counter = try route(.counter)
        var first: [MiniAppRoute?] = []
        var second: [MiniAppRoute?] = []
        let a = router.register(isActive: true) { first.append($0) }
        let b = router.register(isActive: false) { second.append($0) }
        router.open(counter)
        XCTAssertEqual(first, [counter])
        XCTAssertTrue(second.isEmpty)
        router.update(b, isActive: true)
        router.open(nil)
        XCTAssertEqual(second, [nil])
        XCTAssertEqual(first, [counter])
        router.update(a, isActive: true) // An unchanged phase does not steal focus.
        router.open(counter)
        XCTAssertEqual(second, [nil, counter])
        router.update(a, isActive: false)
        router.update(a, isActive: true)
        router.open(counter)
        XCTAssertEqual(first, [counter, counter])
        router.unregister(a)
        router.open(nil)
        XCTAssertEqual(second, [nil, counter, nil])
        router.unregister(b)
        router.update(a, isActive: true) // Stale registrations cannot return.
        router.open(counter)
        var replacement: [MiniAppRoute?] = []
        router.register(isActive: true) { replacement.append($0) }
        XCTAssertEqual(replacement, [counter])
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second.count, 3)
    }

    @MainActor
    func testColdStartLatestLocationAndInactiveFallback() throws {
        let router = MiniAppSceneRouter()
        let counter = try route(.counter)
        router.open(counter)
        router.open(nil)
        var delivered: [MiniAppRoute?] = []
        router.register(isActive: false) { delivered.append($0) }
        XCTAssertEqual(delivered, [nil], "List request must not disappear as an empty optional")
        router.open(counter)
        XCTAssertEqual(delivered, [nil, counter])
        var later: [MiniAppRoute?] = []
        router.register(isActive: false) { later.append($0) }
        router.open(nil)
        XCTAssertEqual(later, [nil])
        XCTAssertEqual(delivered.count, 2)
    }

    @MainActor
    func testReentrantRoutingUsesTheSurvivingSceneAfterCurrentDelivery() throws {
        let router = MiniAppSceneRouter()
        let counter = try route(.counter)
        var events: [String] = []
        var firstID: UUID?
        firstID = router.register(isActive: true) { _ in
            events.append("first begins")
            if let firstID { router.unregister(firstID) }
            router.register(isActive: true) { _ in events.append("replacement") }
            router.open(nil)
            events.append("first ends")
        }
        router.open(counter)
        XCTAssertEqual(events, ["first begins", "first ends", "replacement"])
    }
}
