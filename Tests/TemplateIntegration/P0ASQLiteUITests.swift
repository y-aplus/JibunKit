import XCTest

/// Copied only into the isolated signed CI host by the integration workflow.
@MainActor
final class P0ASQLiteUITests: XCTestCase {
    func testNativeMaintenanceClosesReopensRollsBackAndPreservesOtherOwner() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let launcher = app.buttons["miniapp.p0a-sqlite"]
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<20 where !launcher.exists { list.swipeUp() }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), app.debugDescription)
        launcher.tap()
        let run = app.buttons["p0a.sqlite.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 10), app.debugDescription)
        run.tap()

        let expected = "normal a=11 b=22; migrated a=31 label=1 b=22; rollback a=31 label=1 b=22; reset a=0 label=0 b=22"
        let result = app.staticTexts.matching(identifier: "p0a.sqlite.result")
            .matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
        print("P0A_SQLITE_UI \(expected)")
    }
}
