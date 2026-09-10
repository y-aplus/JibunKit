import XCTest

/// Copied only into the temporary signed Feature-validation host by CI.
@MainActor
final class SpotlightOwnershipUITests: XCTestCase {
    func testNativeIndexPreservesOtherOwnerAfterOwnedDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        let probe = app.buttons["miniapp.spotlight-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), app.debugDescription)
        probe.tap()
        let run = app.buttons["spotlight.ownership.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), app.debugDescription)
        run.tap()

        let passed = app.staticTexts.matching(identifier: "spotlight.ownership.result")
            .matching(NSPredicate(format: "label == %@", "passed")).firstMatch
        XCTAssertTrue(passed.waitForExistence(timeout: 40), app.debugDescription)
        print("SPOTLIGHT_OWNERSHIP_UI result=passed")
    }
}
