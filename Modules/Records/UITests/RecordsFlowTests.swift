import XCTest

@MainActor
final class RecordsFlowTests: XCTestCase {
    func testCreateCancelEditPersistSearchAndDelete() throws {
        continueAfterFailure = false
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
        func openRecord() {
            // The default row-center tap includes blank space beside short text.
            // Assert the actual destination, without a retry tap hiding lost input.
            tap(row())
            XCTAssertTrue(app.buttons["records.edit"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10), app.debugDescription)
        }
        tap(app.buttons["records.add"])
        XCTAssertFalse(app.buttons["records.save"].isEnabled)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText("Original body")
        tap(app.buttons["records.save"])
        openRecord()
        XCTAssertEqual(app.staticTexts["records.body"].label, "Original body")
        tap(app.buttons["records.edit"])
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText(" cancelled")
        tap(app.buttons["キャンセル"])
        XCTAssertEqual(app.staticTexts["records.body"].label, "Original body")
        tap(app.buttons["records.edit"])
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText(" edited")
        let editedBody = try XCTUnwrap(app.textViews["records.editor.body"].value as? String)
        XCTAssertTrue(editedBody.contains("Original body"))
        XCTAssertTrue(editedBody.contains(" edited"))
        XCTAssertFalse(editedBody.contains("cancelled"))
        tap(app.buttons["records.save"])
        let expected = NSPredicate(format: "label == %@", editedBody)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: app.staticTexts["records.body"])], timeout: 10), .completed)
        app.terminate()
        app.launch()
        openRecord()
        XCTAssertEqual(app.staticTexts["records.body"].label, editedBody)
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
