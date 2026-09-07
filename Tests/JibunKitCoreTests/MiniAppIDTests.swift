import XCTest
@testable import JibunKitCore

final class MiniAppIDTests: XCTestCase {
    func testDottedIDsCannotAliasAnotherFeaturesStorageOrNotifications() {
        let parent = MiniAppID("zaiko")
        let child = MiniAppID("zaiko.backup")
        XCTAssertNotEqual(parent.storageKey("backup.latest"), child.storageKey("latest"))
        XCTAssertEqual(child.storageKey("latest"), "zaiko%2Ebackup.latest")
        XCTAssertFalse(MiniAppID("zaiko%2Ebackup").isValid)
        let notificationChild = MiniAppID("zaiko.notification.extra")
        XCTAssertFalse(notificationChild.notificationRequestIdentifier.hasPrefix(
            parent.notificationRequestIdentifier + "."
        ))
        XCTAssertEqual(parent.storageKey("backup.latest"), "zaiko.backup.latest")
        XCTAssertEqual(MiniAppID("counter").storageKey("value"), "counter.value")
        XCTAssertEqual(MiniAppID("reminder").storageKey("message"), "reminder.message")
        XCTAssertEqual(MiniAppID("reminder").notificationRequestIdentifier,
                       "jibunkit.reminder.notification")
    }

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

    func testValidatorAcceptsRegisteredIdentifiers() {
        let issues = MiniAppValidator.validate(ids: [
            MiniAppID("counter"),
            MiniAppID("reminder"),
        ])

        XCTAssertTrue(issues.isEmpty)
    }

    func testValidatorReportsInvalidAndCollidingIdentifiers() {
        let issues = MiniAppValidator.validate(ids: [
            MiniAppID("counter"),
            MiniAppID("counter"),
            MiniAppID("Bad ID"),
        ])

        XCTAssertTrue(issues.contains(.invalidID(rawValue: "Bad ID")))
        XCTAssertTrue(issues.contains(.duplicateID(rawValue: "counter")))
        XCTAssertTrue(issues.contains(.duplicateStorageNamespace(namespace: "counter")))
        XCTAssertTrue(issues.contains(
            .duplicateNotificationRequestIdentifier(
                identifier: "jibunkit.counter.notification"
            )
        ))
    }
}
