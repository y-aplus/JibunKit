import XCTest

/// Copied only into the temporary Notes-integrated host by CI.
@MainActor
final class GeneratedFeatureUITests: XCTestCase {
    func testRecordsUsesIndependentHostStorage() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        tap(app.buttons["miniapp.counter"])
        let counterValue = app.staticTexts["counter.value"].label
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.records"])
        tap(app.buttons["records.add"])
        let title = "Hosted-" + UUID().uuidString.prefix(8)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText("Host record")
        tap(app.buttons["records.save"])
        app.terminate()
        app.launch()
        tap(app.buttons["miniapp.records"])
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let recordID = String(row.identifier.dropFirst("records.row.".count))
        XCTAssertNotNil(UUID(uuidString: recordID))
        tap(row)
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
        tap(app.navigationBars.buttons["記録"])
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=invalid")))
        XCTAssertTrue(app.staticTexts["counter.value"].exists)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=\(recordID)")))
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
    }

    func testGeneratedFeatureCoexistsAndRoutesInHost() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let notes = app.buttons["miniapp.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["miniapp.counter"].exists)
        XCTAssertTrue(app.buttons["miniapp.reminder"].exists)
        notes.tap()
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["ミニアプリ"].tap()
        let counter = app.buttons["miniapp.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.tap()
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["counter.value"].exists)
        app.navigationBars.buttons["ミニアプリ"].tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
    }
}
