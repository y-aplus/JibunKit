import XCTest
@testable import JibunKitCore

final class MiniAppNotificationIdentifierTests: XCTestCase {
    func testMultipleKeysAreStableAndDistinct() {
        let context = MiniAppContext(id: MiniAppID("planner"))
        let keys = ["", "a", "a.b", "a/b", "%2E", "予定1", "予定2", "💊", "\u{0}"]
        let identifiers = keys.map { context.notificationRequestIdentifier(for: $0) }
        XCTAssertEqual(Set(identifiers).count, keys.count)
        XCTAssertFalse(identifiers.contains(context.notificationRequestIdentifier))
        for (key, identifier) in zip(keys, identifiers) {
            XCTAssertEqual(identifier, context.notificationRequestIdentifier(for: key))
            XCTAssertTrue(context.ownsNotificationRequestIdentifier(identifier))
        }
    }

    func testOwnershipCannotSelectAnotherFeaturesNotifications() {
        let contexts = ["planner", "planner.notification.extra", "planner2", "planner.extra"]
            .map { MiniAppContext(id: MiniAppID($0)) }
        for owner in contexts {
            for other in contexts {
                XCTAssertEqual(owner.ownsNotificationRequestIdentifier(other.notificationRequestIdentifier), owner == other)
                XCTAssertEqual(owner.ownsNotificationRequestIdentifier(other.notificationRequestIdentifier(for: "same")), owner == other)
            }
        }
        XCTAssertFalse(contexts[0].ownsNotificationRequestIdentifier("unrelated"))
        XCTAssertEqual(MiniAppContext(id: MiniAppID("reminder")).notificationRequestIdentifier,
                       "jibunkit.reminder.notification")
    }
}
