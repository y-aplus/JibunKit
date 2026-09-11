import XCTest

/// Copied only into the temporary signed Feature-validation host by CI.
@MainActor
final class NowPlayingOwnershipUITests: XCTestCase {
    func testTwoNativeNowPlayingSessionsKeepFeatureStateIndependent() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        let probe = app.buttons["miniapp.now-playing-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), app.debugDescription)
        probe.tap()
        let run = app.buttons["now-playing.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), app.debugDescription)
        run.tap()

        let passed = app.staticTexts.matching(identifier: "now-playing.result")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "passed:")).firstMatch
        XCTAssertTrue(passed.waitForExistence(timeout: 20), app.debugDescription)
        print("NOW_PLAYING_NATIVE_RESULT \(passed.label)")
    }
}
