import XCTest
@testable import AppbaseCore

final class MiniAppIDTests: XCTestCase {
    func testMiniAppIdentifiersAndNamespacesDoNotCollide() {
        let miniApps = MiniAppID.allCases

        XCTAssertEqual(
            Set(miniApps.map(\.rawValue)).count,
            miniApps.count
        )
        XCTAssertEqual(
            Set(miniApps.map(\.storageNamespace)).count,
            miniApps.count
        )
        XCTAssertEqual(
            Set(miniApps.map(\.notificationRequestIdentifier)).count,
            miniApps.count
        )
    }

    func testNotificationPayloadResolvesRegisteredTarget() {
        let result = MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: "reminder",
        ])

        XCTAssertEqual(result, .reminder)
    }

    func testNotificationPayloadRejectsUnknownOrInvalidTarget() {
        XCTAssertNil(MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: "removed-mini-app",
        ]))
        XCTAssertNil(MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: 42,
        ]))
        XCTAssertNil(MiniAppNotificationRoute.resolve(userInfo: [:]))
    }
}
