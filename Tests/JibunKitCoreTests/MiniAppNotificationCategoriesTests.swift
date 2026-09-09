#if canImport(UserNotifications)
import XCTest
import UserNotifications
import JibunKitCore

final class MiniAppNotificationCategoriesTests: XCTestCase {
    @MainActor
    func testDynamicReplacementAndRemovalPreserveOtherOwnerAndRejectInvalidUpdate() throws {
        let first = MiniAppContext(id: MiniAppID("first"))
        let second = MiniAppContext(id: MiniAppID("second"))
        func category(_ context: MiniAppContext, _ key: String) -> UNNotificationCategory {
            UNNotificationCategory(identifier: context.notificationCategoryIdentifier(for: key),
                actions: [], intentIdentifiers: [], options: [])
        }
        let a = category(first, "old")
        let a2 = category(first, "new")
        let b = category(second, "item")
        var installations: [Set<String>] = []
        let registry = MiniAppNotificationCategoryRegistry { installations.append(Set($0.map(\.identifier))) }
        try registry.configure([first.id: [a], second.id: [b]])
        try registry.replace(for: first.id, with: [a2])
        XCTAssertEqual(installations.last, Set([a2.identifier, b.identifier]))
        XCTAssertThrowsError(try registry.replace(for: first.id, with: [b]))
        XCTAssertThrowsError(try registry.replace(for: first.id, with: [a2, a2]))
        XCTAssertThrowsError(try registry.replace(for: MiniAppID("unknown"), with: []))
        XCTAssertEqual(installations.count, 2)
        // A later successful change proves failed candidates did not corrupt stored state.
        try registry.replace(for: second.id, with: [])
        XCTAssertEqual(installations.last, Set([a2.identifier]))
        try registry.replace(for: second.id, with: [b])
        try registry.replace(for: first.id, with: [])
        XCTAssertEqual(installations.last, Set([b.identifier]))
    }

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
