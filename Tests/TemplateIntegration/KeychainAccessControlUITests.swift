import XCTest

/// Copied only into the temporary access-control host by CI.
@MainActor
final class KeychainAccessControlUITests: XCTestCase {
    func testProtectedUpdateFailsWithoutUIAndPreservesBothOwners() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let feature = app.buttons["miniapp.keychain-access-control-probe"]
        XCTAssertTrue(feature.waitForExistence(timeout: 10), app.debugDescription)
        feature.tap()

        let run = app.buttons["keychain.access-control.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), app.debugDescription)
        run.tap()

        let result = app.staticTexts.matching(identifier: "keychain.access-control.result")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "passed:"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(result.label.contains("update=after"))
        XCTAssertTrue(result.label.contains("protected=present"))
        XCTAssertTrue(result.label.contains("other=other"))
    }
}
