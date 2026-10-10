import Foundation
import XCTest
import JibunKitCore

@MainActor
final class MiniAppBadgeTests: XCTestCase {
    func testIconShowsTheSumOfEnabledOwnersWithoutOverwriting() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "badge-" + UUID().uuidString))
        var shown: [Int] = []
        let badge = MiniAppBadgeCoordinator(defaults: defaults) { shown.append($0) }
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        try await badge.setCount(3, for: a)
        try await badge.setCount(2, for: b)
        XCTAssertEqual(shown, [3, 5])
        try await badge.setEnabledOwners([b])
        XCTAssertEqual(badge.total, 2)
        XCTAssertEqual(badge.count(for: a), 3)
        try await badge.setEnabledOwners([a, b])
        try await badge.setCount(-4, for: b)
        XCTAssertEqual(badge.count(for: b), 0)
        try await badge.removeCount(for: a)
        XCTAssertEqual(shown, [3, 5, 2, 5, 3, 0])
        await XCTAssertThrowsErrorAsync { try await badge.setCount(1, for: MiniAppID("Bad")) }
    }

    func testFocusFilterHidesOwnersWithoutForgettingTheirCounts() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "badge-" + UUID().uuidString))
        var shown: [Int] = []
        let badge = MiniAppBadgeCoordinator(defaults: defaults) { shown.append($0) }
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        try await badge.setCount(3, for: a)
        try await badge.setCount(2, for: b)
        try await badge.setFocusedOwners([b])
        try await badge.setEnabledOwners([a])
        try await badge.setFocusedOwners(nil)
        XCTAssertEqual(shown, [3, 5, 2, 0, 3])
        XCTAssertEqual(badge.count(for: b), 2)
    }

    func testStoredCountsSurviveANewCoordinatorAndIgnoreMalformedValues() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "badge-" + UUID().uuidString))
        try await MiniAppBadgeCoordinator(defaults: defaults) { _ in }.setCount(4, for: MiniAppID("a"))
        defaults.set(["a": 4, "b": "x", "c": -1], forKey: MiniAppBadgeCoordinator.defaultStorageKey)
        let reopened = MiniAppBadgeCoordinator(defaults: defaults) { _ in }
        XCTAssertEqual(reopened.total, 4)
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(_ operation: () async throws -> Void,
                                       file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await operation()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
