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
}
#endif
