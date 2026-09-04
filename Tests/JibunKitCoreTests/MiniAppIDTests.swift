import XCTest
@testable import JibunKitCore

final class MiniAppIDTests: XCTestCase {
    func testMiniAppIdentifiersAndNamespacesDoNotCollide() {
        let miniApps = [MiniAppID("counter"), MiniAppID("reminder")]

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
        let reminder = MiniAppID("reminder")
        let result = MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: "reminder",
        ], registeredIDs: [MiniAppID("counter"), reminder])

        XCTAssertEqual(result, reminder)
    }

    func testNotificationPayloadRejectsUnknownOrInvalidTarget() {
        let registeredIDs = Set([MiniAppID("counter"), MiniAppID("reminder")])

        XCTAssertNil(MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: "removed-mini-app",
        ], registeredIDs: registeredIDs))
        XCTAssertNil(MiniAppNotificationRoute.resolve(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: 42,
        ], registeredIDs: registeredIDs))
        XCTAssertNil(MiniAppNotificationRoute.resolve(
            userInfo: [:],
            registeredIDs: registeredIDs
        ))
    }

    func testMiniAppIDValidationAcceptsStableIdentifiers() {
        XCTAssertTrue(MiniAppID("zaiko").isValid)
        XCTAssertTrue(MiniAppID("tabi-plot.v2").isValid)
        XCTAssertTrue(MiniAppID("trip_planner3").isValid)
    }

    func testMiniAppIDValidationRejectsUnsafeIdentifiers() {
        XCTAssertFalse(MiniAppID("").isValid)
        XCTAssertFalse(MiniAppID("TabiPlot").isValid)
        XCTAssertFalse(MiniAppID("3trip").isValid)
        XCTAssertFalse(MiniAppID("trip planner").isValid)
    }

    func testMiniAppContextDerivesNamespacedValues() {
        let context = MiniAppContext(id: MiniAppID("zaiko"))

        XCTAssertEqual(context.storageKey("state"), "zaiko.state")
        XCTAssertEqual(context.notificationRequestIdentifier, "jibunkit.zaiko.notification")
        XCTAssertEqual(
            context.notificationUserInfo[MiniAppNotificationRoute.miniAppIDUserInfoKey],
            "zaiko"
        )
    }
}
