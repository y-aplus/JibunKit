import XCTest

@MainActor
final class BackgroundTasksNativeUITests: XCTestCase {
    private func waitForResult(
        _ result: XCUIElement,
        successPrefix: String = "passed:",
        timeout: TimeInterval = 30
    ) {
        let finished = NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH 'failed:'",
            successPrefix
        )
        expectation(for: finished, evaluatedWith: result)
        waitForExpectations(timeout: timeout)
    }

    func testTwoOwnersMatchNativePendingRequestsAndCancellationIsScoped() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["backgroundtasks.run"].tap()

        let result = app.staticTexts["backgroundtasks.result"]
        waitForResult(result)
        XCTAssertEqual(
            result.label,
            "passed: wrapper-a=refresh wrapper-b=processing native-a=refresh native-b=processing a-cancelled b-pending"
        )
    }

    /// Real-device diagnostic. The compile-only Simulator lane intentionally
    /// does not select this method because native scheduling is unavailable.
    func testSharedRefreshPersistsBAndKeepsOneNativeRequestAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let result = app.staticTexts["backgroundtasks.shared.result"]
        app.buttons["backgroundtasks.shared.prepare"].tap()
        waitForResult(result, successPrefix: "passed: shared prepared")
        XCTAssertTrue(result.label.hasPrefix("passed: shared prepared"), result.label)
        let prepared = result.label
        let expression = try NSRegularExpression(pattern: #"saved-b=([0-9A-Fa-f-]{36})"#)
        let range = NSRange(prepared.startIndex..., in: prepared)
        let match = try XCTUnwrap(expression.firstMatch(in: prepared, range: range))
        let generationRange = try XCTUnwrap(Range(match.range(at: 1), in: prepared))
        let expectedGeneration = String(prepared[generationRange])

        app.terminate()
        app.launch()
        app.buttons["backgroundtasks.shared.verify"].tap()
        waitForResult(result, successPrefix: "passed: shared restored")
        XCTAssertTrue(result.label.hasPrefix("passed: shared restored"), result.label)
        XCTAssertTrue(result.label.contains("b=\(expectedGeneration)"), result.label)
        XCTAssertTrue(result.label.contains("native-count=1 earliest=preserved"), result.label)

        app.buttons["backgroundtasks.shared.cleanup"].tap()
        waitForResult(result, successPrefix: "passed: shared cleanup")
        XCTAssertEqual(result.label, "passed: shared cleanup a=0 b=0")
    }
}
