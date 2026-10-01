#if canImport(CoreSpotlight)
import CoreSpotlight
import Foundation
import XCTest
import JibunKitCore

final class MiniAppSpotlightRouteTests: XCTestCase {
    func testOpaqueLocalIDsRoundTripOnlyForTheirOwner() {
        let a = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("a")))
        let b = MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID("a.spotlight")))
        for local in ["", "same", "日本語 📓/detail?x=1", "A.B+C="] {
            let identifier = a.itemIdentifier(for: local)
            XCTAssertEqual(a.localIdentifier(for: identifier), local)
            XCTAssertNil(b.localIdentifier(for: identifier))
        }
        for suffix in ["?", "YQ", "YQ==\n", "/w=="] {
            XCTAssertNil(a.localIdentifier(for: a.domainIdentifier + "." + suffix))
        }
    }

    func testNativeSelectedItemActivityResolvesRegisteredOwnerOnly() {
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        let namespace = MiniAppSpotlightNamespace(context: MiniAppContext(id: a))
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: namespace.itemIdentifier(for: "record/42")]
        let route = MiniAppSpotlightRoute.resolve(activity, registeredIDs: [a, b, MiniAppID("invalid/id")])
        XCTAssertEqual(route?.id, a)
        XCTAssertEqual(route?.destination, "record/42")
        XCTAssertNil(MiniAppSpotlightRoute.resolve(activity, registeredIDs: [b]))
        let query = NSUserActivity(activityType: CSQueryContinuationActionType)
        query.userInfo = activity.userInfo
        XCTAssertNil(MiniAppSpotlightRoute.resolve(query, registeredIDs: [a]))
        activity.userInfo = [CSSearchableItemActivityIdentifier: 42]
        XCTAssertNil(MiniAppSpotlightRoute.resolve(activity, registeredIDs: [a]))
        activity.userInfo = [CSSearchableItemActivityIdentifier: namespace.domainIdentifier + ".?"]
        XCTAssertNil(MiniAppSpotlightRoute.resolve(activity, registeredIDs: [a]))
    }

    func testSearchContinuationQueryIsReadOnlyFromItsActivityType() {
        let query = NSUserActivity(activityType: CSQueryContinuationActionType)
        query.userInfo = [CSSearchQueryString: "  sbux \n"]
        XCTAssertEqual(MiniAppSearchContinuation.query(from: query), "sbux")
        query.userInfo = [CSSearchQueryString: " \n"]
        XCTAssertNil(MiniAppSearchContinuation.query(from: query))
        query.userInfo = [CSSearchQueryString: 42]
        XCTAssertNil(MiniAppSearchContinuation.query(from: query))
        let selected = NSUserActivity(activityType: CSSearchableItemActionType)
        selected.userInfo = [CSSearchQueryString: "sbux"]
        XCTAssertNil(MiniAppSearchContinuation.query(from: selected))
    }

    @MainActor
    func testSearchContinuationOffersOnlyRegisteredAcceptingOwnersInOrder() {
        let a = MiniAppID("a")
        let b = MiniAppID("b")
        let c = MiniAppID("c")
        let d = MiniAppID("d")
        let registrations: [MiniAppSearchContinuation.Registration] = [
            .init(id: a) { "search:" + $0 },
            .init(id: b) { _ in nil },
            .init(id: c) { "search:" + $0 },
            .init(id: d) { _ in "bad\u{0}destination" },
        ]
        let routes = MiniAppSearchContinuation.candidates(for: "mac", registrations: registrations,
                                                          registeredIDs: [a, b, d])
        XCTAssertEqual(routes.map(\.id), [a])
        XCTAssertEqual(routes.first?.destination, "search:mac")
        let both = MiniAppSearchContinuation.candidates(for: "mac", registrations: registrations,
                                                        registeredIDs: [a, c])
        XCTAssertEqual(both.map(\.id), [a, c])
    }
}
#endif
