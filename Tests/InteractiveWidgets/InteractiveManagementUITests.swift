import XCTest

@MainActor
final class InteractiveManagementUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    func testNormalManagementRetainsDisabledStateAndReregistersOnlyA() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        try open("b")
        let b = app.staticTexts["interactive-b.values"].label
        tap("miniapp.back-to-list")
        try open("a")
        tap("interactive-a.delete")
        expect("interactive-a.values", "second-id: 30")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.disable.interactive-a")
        expect("management.status.interactive-a", "無効（データを保持）")
        tap("management.enable.interactive-a")
        expect("management.status.interactive-a", "有効")
        app.terminate()
        app.launch()
        try open("a")
        expect("interactive-a.values", "second-id: 30")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.delete.interactive-a")
        let confirm = app.alerts.buttons["削除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expect("management.status.interactive-a", "削除済み", timeout: 60)
        tap("management.enable.interactive-a")
        expect("management.status.interactive-a", "有効")
        app.terminate()
        app.launch()
        try open("a")
        expect("interactive-a.values", "same-id: 10\nsecond-id: 30")
        tap("miniapp.back-to-list")
        try open("b")
        expect("interactive-b.values", b)
    }
    private func open(_ owner: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/interactive-" + owner)))
        XCTAssertTrue(app.staticTexts["interactive-\(owner).values"].waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'second-id:'"),
            object: app.staticTexts["interactive-\(owner).values"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }
    private func tap(_ id: String) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
        element.tap()
    }
    private func expect(_ id: String, _ label: String, timeout: TimeInterval = 20) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
}
