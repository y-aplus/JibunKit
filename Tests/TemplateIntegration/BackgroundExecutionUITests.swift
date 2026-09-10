import XCTest

/// Copied only into the temporary signed Feature-validation host by CI.
@MainActor
final class BackgroundExecutionUITests: XCTestCase {
    func testNativeAssertionsAreOwnedPerFeatureAndRuntime() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        let probe = app.buttons["miniapp.background-execution-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), app.debugDescription)
        probe.tap()
        let run = app.buttons["background.execution.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), app.debugDescription)
        run.tap()

        let passed = app.staticTexts.matching(identifier: "background.execution.result")
            .matching(NSPredicate(format: "label == %@", "passed")).firstMatch
        XCTAssertTrue(passed.waitForExistence(timeout: 20), app.debugDescription)
        print("BACKGROUND_EXECUTION_UI result=passed")
    }
}
