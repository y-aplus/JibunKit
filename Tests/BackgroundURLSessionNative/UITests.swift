import XCTest

@MainActor
final class BackgroundURLSessionNativeUITests: XCTestCase {
    func testTwoOwnersDownloadAndCancellationRemainsScoped() {
        let app = XCUIApplication()
        let baseURL = "__BACKGROUND_URLSESSION_BASE_URL__"
        XCTAssertFalse(baseURL.hasPrefix("__"), "Native fixture base URL was not injected")
        app.launchEnvironment["BACKGROUND_URLSESSION_BASE_URL"] = baseURL
        app.launch()
        app.buttons["background-urlsession.run"].tap()

        let result = app.staticTexts["background-urlsession.result"]
        let finished = NSPredicate(
            format: "label BEGINSWITH 'passed:' OR label BEGINSWITH 'failed:'")
        expectation(for: finished, evaluatedWith: result)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(
            result.label,
            "passed: a-destination=owner-a b-destination=owner-b a-cancelled b-continued native-downloads=3"
        )
    }
}
