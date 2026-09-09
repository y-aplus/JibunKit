#if canImport(UserNotifications)
import UserNotifications
import XCTest
@testable import JibunKitCore

final class MiniAppNotificationPresentationTests: XCTestCase {
    @MainActor
    func testOwnerCanSilenceWithoutChangingAnotherOwnersPresentation() {
        let first = MiniAppID("first")
        let second = MiniAppID("second")
        let event = MiniAppForegroundNotification(requestIdentifier: "request", categoryIdentifier: "category", destination: "detail")
        var received: [MiniAppID] = []
        let lookup: (MiniAppID) -> (@MainActor (MiniAppForegroundNotification) -> UNNotificationPresentationOptions)? = { owner in
            { notification in
                received.append(owner)
                XCTAssertEqual(notification, event)
                return owner == first ? [] : [.list]
            }
        }
        XCTAssertEqual(MiniAppNotificationPresentation.options(for: event,
            route: MiniAppRoute(id: first, destination: "detail"), policyForOwner: lookup), [])
        XCTAssertEqual(MiniAppNotificationPresentation.options(for: event,
            route: MiniAppRoute(id: second, destination: "detail"), policyForOwner: lookup), [.list])
        XCTAssertEqual(received, [first, second])
    }

    @MainActor
    func testMissingOwnerOrPolicyPreservesLegacyDefault() {
        let event = MiniAppForegroundNotification(requestIdentifier: "legacy", categoryIdentifier: "", destination: nil)
        let expected: UNNotificationPresentationOptions = [.banner, .list, .sound]
        XCTAssertEqual(MiniAppNotificationPresentation.options(for: event, route: nil,
            policyForOwner: { _ in XCTFail("Invalid route must not select a Feature"); return nil }), expected)
        XCTAssertEqual(MiniAppNotificationPresentation.options(for: event,
            route: MiniAppRoute(id: MiniAppID("removed"), destination: nil), policyForOwner: { _ in nil }), expected)
    }
}
#endif
