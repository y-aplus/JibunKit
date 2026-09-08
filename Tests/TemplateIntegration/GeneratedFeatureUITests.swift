import XCTest

/// Copied only into the temporary Notes-integrated host by CI.
@MainActor
final class GeneratedFeatureUITests: XCTestCase {
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
