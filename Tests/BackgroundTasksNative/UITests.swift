import XCTest

@MainActor
final class BackgroundTasksNativeUITests: XCTestCase {
    func testTwoOwnersMatchNativePendingRequestsAndCancellationIsScoped() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["backgroundtasks.run"].tap()

        let result = app.staticTexts["backgroundtasks.result"]
        let finished = NSPredicate(
            format: "label BEGINSWITH 'passed:' OR label BEGINSWITH 'failed:'")
        expectation(for: finished, evaluatedWith: result)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(
            result.label,
            "passed: wrapper-a=refresh wrapper-b=processing native-a=refresh native-b=processing a-cancelled b-pending"
        )
    }
}
