import XCTest

final class BackgroundURLSessionNativeUITests: XCTestCase {
    func testTwoOwnersDownloadAndCancellationRemainsScoped() {
        let app = XCUIApplication()
        app.launchEnvironment["BACKGROUND_URLSESSION_BASE_URL"] = ProcessInfo.processInfo.environment[
            "BACKGROUND_URLSESSION_BASE_URL"
        ]
        app.launch()
        app.buttons["background-urlsession.run"].tap()

        let result = app.staticTexts["background-urlsession.result"]
        let passed = NSPredicate(format: "label BEGINSWITH 'passed:'")
        expectation(for: passed, evaluatedWith: result)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(
            result.label,
            "passed: a-destination=owner-a b-destination=owner-b a-cancelled b-continued native-downloads=3"
        )
    }
}

