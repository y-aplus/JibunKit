#if canImport(UserNotifications)
import XCTest
import UserNotifications
import JibunKitCore

final class MiniAppNotificationCategoriesTests: XCTestCase {
    func testIndependentCategoriesPreserveNativeActionsAndOptions() throws {
        let first = MiniAppContext(id: MiniAppID("first"))
        let second = MiniAppContext(id: MiniAppID("second"))
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        func category(_ context: MiniAppContext) -> UNNotificationCategory {
            UNNotificationCategory(identifier: context.notificationCategoryIdentifier(for: "message"),
                actions: [reply], intentIdentifiers: [], options: [.customDismissAction])
        }
        let a = category(first)
        let b = category(second)
        let merged = try MiniAppNotificationCategories.merged([first.id: [a], second.id: [b]])
        XCTAssertEqual(merged.count, 2)
        XCTAssertNotEqual(a.identifier, b.identifier)
        for value in merged {
            XCTAssertTrue(value.options.contains(.customDismissAction))
            let action = try XCTUnwrap(value.actions.first as? UNTextInputNotificationAction)
            XCTAssertEqual(action.identifier, "reply")
            XCTAssertEqual(action.textInputButtonTitle, "Send")
        }
    }

    func testDuplicateAndForeignCategoriesAreRejectedBeforeInstallation() {
        let owner = MiniAppContext(id: MiniAppID("owner"))
        let category = UNNotificationCategory(identifier: owner.notificationCategoryIdentifier(for: "item"),
            actions: [], intentIdentifiers: [], options: [])
        XCTAssertThrowsError(try MiniAppNotificationCategories.merged([owner.id: [category, category]]))
        XCTAssertThrowsError(try MiniAppNotificationCategories.merged([MiniAppID("other"): [category]]))
    }
}
#endif
