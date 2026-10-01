import Foundation
import XCTest
import JibunKitCore

final class MiniAppNotificationOwnerTests: XCTestCase {
    private let a = MiniAppID("a")
    private let ab = MiniAppID("a.b")

    func testPayloadOwnerWinsAndIsNeverReplacedByIdentifierMatching() {
        let context = MiniAppContext(id: a)
        let request = context.notificationRequestIdentifier(for: "x")
        XCTAssertEqual(MiniAppNotificationOwner.resolve(requestIdentifier: request, categoryIdentifier: "",
            userInfo: ["JibunKitMiniAppID": "a.b"], candidates: [a, ab]), ab)
        XCTAssertNil(MiniAppNotificationOwner.resolve(requestIdentifier: request, categoryIdentifier: "",
            userInfo: ["JibunKitMiniAppID": "missing"], candidates: [a, ab]))
        XCTAssertNil(MiniAppNotificationOwner.resolve(requestIdentifier: request, categoryIdentifier: "",
            userInfo: ["JibunKitMiniAppID": 3], candidates: [a]))
    }

    func testRequestOrCategoryNamespaceSelectsExactlyOneOwner() {
        let context = MiniAppContext(id: ab)
        XCTAssertEqual(MiniAppNotificationOwner.resolve(requestIdentifier: context.notificationRequestIdentifier(for: "k"),
            categoryIdentifier: "", userInfo: [:], candidates: [a, ab]), ab)
        XCTAssertEqual(MiniAppNotificationOwner.resolve(requestIdentifier: "remote-id",
            categoryIdentifier: context.notificationCategoryIdentifier(for: "reply"), userInfo: [:], candidates: [a, ab]), ab)
        XCTAssertNil(MiniAppNotificationOwner.resolve(requestIdentifier: "remote-id", categoryIdentifier: "other",
            userInfo: [:], candidates: [a, ab]))
        XCTAssertEqual(context.notificationCategoryIdentifier(for: "x"), "jibunkit.a%2Eb.category.eA==")
    }
}
