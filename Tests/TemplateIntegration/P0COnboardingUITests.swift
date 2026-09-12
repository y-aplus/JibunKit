import XCTest

@MainActor
final class P0COnboardingUITests: XCTestCase {
    func testCompiledPackagesAreRegisteredAndNotesUsesNormalURL() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["--p0c-omit-notes"]
        app.launch()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p0-c-onboarding")))
        let missing = app.staticTexts["p0c.connection.result"]
        XCTAssertTrue(missing.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(missing.label.contains("MiniAppRegistry.swift"), missing.label)
        XCTAssertTrue(missing.label.contains("missingExpectedID"), missing.label)
        XCTAssertTrue(missing.label.contains("notes"), missing.label)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(missing.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Notes"].exists, app.debugDescription)
        app.terminate()

        // Correct the registration while keeping the very same linked packages.
        app.launchArguments = []
        app.launch()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p0-c-onboarding")))
        let result = app.staticTexts["p0c.connection.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(result.label, "passed: counter,notes,records,reminder", app.debugDescription)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
