import XCTest

@MainActor
final class RecordsFlowTests: XCTestCase {
    func testCreateCancelEditPersistSearchAndDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let title = "Record-" + UUID().uuidString.prefix(8)
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        func row() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        }
        tap(app.buttons["records.add"])
        XCTAssertFalse(app.buttons["records.save"].isEnabled)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText("Original body")
        tap(app.buttons["records.save"])
        tap(row())
        XCTAssertEqual(app.staticTexts["records.body"].label, "Original body")
        tap(app.buttons["records.edit"])
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText(" cancelled")
        tap(app.buttons["キャンセル"])
        XCTAssertEqual(app.staticTexts["records.body"].label, "Original body")
        tap(app.buttons["records.edit"])
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText(" edited")
        tap(app.buttons["records.save"])
        let expected = NSPredicate(format: "label == %@", "Original body edited")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: app.staticTexts["records.body"])], timeout: 10), .completed)
        app.terminate()
        app.launch()
        tap(row())
        XCTAssertEqual(app.staticTexts["records.body"].label, "Original body edited")
        tap(app.navigationBars.buttons["記録"])
        app.swipeDown()
        tap(app.searchFields.firstMatch)
        app.searchFields.firstMatch.typeText(String(title))
        XCTAssertTrue(row().waitForExistence(timeout: 5))
        row().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["キャンセル"])
        XCTAssertTrue(row().exists)
        row().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["削除"])
        XCTAssertTrue(row().waitForNonExistence(timeout: 5))
    }
}
