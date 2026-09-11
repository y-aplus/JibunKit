import XCTest

/// Copied only into the temporary signed Feature-validation host by CI.
@MainActor
final class HostLaunchHookUITests: XCTestCase {
    func testTwoFeatureLaunchFactoriesRunOnceBeforeScreenCreation() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        assertLaunchCount(owner: "host-launch-a", app: app)
        app.navigationBars.buttons["ミニアプリ"].tap()
        assertLaunchCount(owner: "host-launch-b", app: app)
    }

    private func assertLaunchCount(owner: String, app: XCUIApplication) {
        let feature = app.buttons["miniapp.\(owner)"]
        XCTAssertTrue(feature.waitForExistence(timeout: 10), app.debugDescription)
        feature.tap()
        let once = app.staticTexts.matching(identifier: "host.launch.\(owner).count")
            .matching(NSPredicate(format: "label == %@", "1")).firstMatch
        XCTAssertTrue(once.waitForExistence(timeout: 10), app.debugDescription)
    }
}

