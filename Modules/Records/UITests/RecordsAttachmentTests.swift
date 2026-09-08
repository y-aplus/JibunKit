import XCTest

@MainActor
final class RecordsAttachmentTests: XCTestCase {
    func testImportPreviewPersistAndDeleteAttachment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--attachment-fixture"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 15))
            element.tap()
        }
        let title = "Attachment-" + UUID().uuidString.prefix(8)
        func row() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        }
        func attachment() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.attachment.")).firstMatch
        }
        tap(app.buttons["records.add"])
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.buttons["records.save"])
        tap(row())
        tap(app.buttons["records.attach"])
        tap(app.buttons["ブラウズ"])
        tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "このiPhone内")).firstMatch)
        tap(app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "RecordsExample")).firstMatch)
        tap(app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "attachment-fixture")).firstMatch)
        XCTAssertTrue(attachment().waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(attachment().label.contains("attachment-fixture.txt"))
        tap(attachment())
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 15))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "records-attachment-preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap(app.buttons["完了"])
        app.terminate()
        app.launch()
        tap(row())
        XCTAssertTrue(attachment().waitForExistence(timeout: 10))
        attachment().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["キャンセル"])
        XCTAssertTrue(attachment().exists)
        attachment().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["削除"])
        XCTAssertTrue(attachment().waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        tap(row())
        XCTAssertTrue(app.buttons["records.attach"].waitForExistence(timeout: 10))
        XCTAssertFalse(attachment().exists)
    }
}
