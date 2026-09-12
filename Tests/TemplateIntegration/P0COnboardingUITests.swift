import XCTest

@MainActor
final class P0COnboardingUITests: XCTestCase {
    func testCompiledPackagesAreRegisteredAndNotesUsesNormalURL() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launch()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p0-c-onboarding")))
        let result = app.staticTexts["p0c.connection.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(result.label, "passed: counter,notes,records,reminder", app.debugDescription)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
