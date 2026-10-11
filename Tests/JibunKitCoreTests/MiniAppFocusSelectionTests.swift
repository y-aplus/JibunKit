import Foundation
import XCTest
import JibunKitCore

@MainActor
final class MiniAppFocusSelectionTests: XCTestCase {
    func testChoiceIsStoredAndAnEmptyChoiceShowsEveryFeature() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "focus-" + UUID().uuidString))
        let selection = MiniAppFocusSelection(defaults: defaults)
        XCTAssertNil(selection.shownIDs)
        XCTAssertTrue(selection.isShown(MiniAppID("a")))

        XCTAssertTrue(selection.apply([MiniAppID("a"), MiniAppID("Bad")]))
        XCTAssertEqual(selection.shownIDs, [MiniAppID("a")])
        XCTAssertFalse(selection.isShown(MiniAppID("b")))
        XCTAssertFalse(selection.apply([MiniAppID("a")]))
        XCTAssertEqual(MiniAppFocusSelection(defaults: defaults).shownIDs, [MiniAppID("a")])

        XCTAssertTrue(selection.apply([]))
        XCTAssertNil(selection.shownIDs)
        XCTAssertNil(defaults.object(forKey: MiniAppFocusSelection.defaultStorageKey))
    }

    func testNotificationFilterCriteriaIsTheOwnerID() {
        XCTAssertEqual(MiniAppContext(id: MiniAppID("records")).notificationFilterCriteria, "records")
    }
}
