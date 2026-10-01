import Foundation
import XCTest
import JibunKitCore

final class MiniAppQuickActionsTests: XCTestCase {
    private let a = MiniAppID("a")
    private let b = MiniAppID("b")
    private let c = MiniAppID("c")

    func testRecentUsageIsNewestFirstDedupedAndIgnoresInvalidValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quick-actions-" + UUID().uuidString))
        let usage = MiniAppRecentUsage(defaults: defaults)
        usage.record(a)
        usage.record(b)
        usage.record(a)
        usage.record(MiniAppID("Invalid"))
        XCTAssertEqual(usage.ids, [a, b])
        usage.remove(a)
        XCTAssertEqual(usage.ids, [b])
        defaults.set(["c", "c", "BAD", 3], forKey: MiniAppRecentUsage.defaultStorageKey)
        XCTAssertEqual(usage.ids, [])
        defaults.set(["c", "c", "BAD"], forKey: MiniAppRecentUsage.defaultStorageKey)
        XCTAssertEqual(usage.ids, [c])
    }

    func testRecentFeaturesComeFirstAndEachGetsOneItemBeforeSeconds() {
        let candidates = [
            MiniAppQuickActions.Candidate(id: a, title: "A", systemImage: "a.circle", actions: [
                .init(title: "A1", systemImage: "1.circle", destination: "one"),
                .init(title: "A2", systemImage: "2.circle", destination: "two"),
                .init(title: "A3", systemImage: "3.circle", destination: "three"),
            ]),
            MiniAppQuickActions.Candidate(id: b, title: "B", systemImage: "b.circle", actions: []),
            MiniAppQuickActions.Candidate(id: c, title: "C", systemImage: "c.circle", actions: [
                .init(title: "Bad", systemImage: "x.circle", destination: "bad\u{0}"),
            ]),
        ]
        let entries = MiniAppQuickActions.entries(recent: [c, MiniAppID("gone"), a], candidates: candidates)
        XCTAssertEqual(entries.map(\.id), [c, a, b, a])
        XCTAssertEqual(entries.map(\.action.title), ["C", "A1", "B", "A2"])
        XCTAssertNil(entries[0].action.destination)
    }

    func testSelectedItemResolvesOnlyAnEnabledOwner() {
        let entry = MiniAppQuickActions.entries(recent: [], candidates: [
            .init(id: a, title: "A", systemImage: "a.circle", actions: [.init(title: "A1", systemImage: "1.circle", destination: "one")]),
        ])[0]
        let info = MiniAppQuickActions.userInfo(for: entry)
        let route = MiniAppQuickActions.route(type: MiniAppQuickActions.shortcutType, userInfo: info, registeredIDs: [a])
        XCTAssertEqual(route?.id, a)
        XCTAssertEqual(route?.destination, "one")
        XCTAssertNil(MiniAppQuickActions.route(type: "other", userInfo: info, registeredIDs: [a]))
        XCTAssertNil(MiniAppQuickActions.route(type: MiniAppQuickActions.shortcutType, userInfo: info, registeredIDs: [b]))
        XCTAssertNil(MiniAppQuickActions.route(type: MiniAppQuickActions.shortcutType, userInfo: nil, registeredIDs: [a]))
    }
}
