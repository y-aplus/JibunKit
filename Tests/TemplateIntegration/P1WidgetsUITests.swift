import XCTest

/// Normal host management/store connection; gallery rendering is tested in the
/// native Widget job and on the later physical 0.8 candidate.
@MainActor
final class P1WidgetsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    func testNormalWidgetDefinitionsDeleteOnlyAAndKeepEmptyAfterRelaunch() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        try open("b")
        tap("widget-feature-b.increment")
        expect("widget-feature-b.status", "updated")
        let savedB = app.staticTexts["widget-feature-b.value"].label
        tap("miniapp.back-to-list")
        try open("a")
        tap("widget-feature-a.increment")
        expect("widget-feature-a.status", "updated")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.disable.owner-a")
        expect("management.status.owner-a", "無効（データを保持）")
        tap("management.enable.owner-a")
        expect("management.status.owner-a", "有効")
        tap("management.delete.owner-a")
        let confirm = app.alerts.buttons["削除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expect("management.status.owner-a", "削除済み")
        tap("management.enable.owner-a")
        expect("management.status.owner-a", "有効")
        app.terminate()
        app.launch()
        try open("a")
        expect("widget-feature-a.value", "--")
        tap("miniapp.back-to-list")
        try open("b")
        expect("widget-feature-b.value", savedB)
    }
    private func open(_ owner: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/owner-" + owner)))
        expect("widget-feature-" + owner + ".status", "ready")
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }
    private func expect(_ id: String, _ value: String) {
        let element = app.staticTexts[id]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 15), .completed, app.debugDescription)
    }
}
