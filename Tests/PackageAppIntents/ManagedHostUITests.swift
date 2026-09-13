import XCTest

@MainActor
final class ManagedHostUITests: XCTestCase {
    func testDisabledAdmissionPersistsAcrossHostRelaunchAndBRemainsUsable() {
        let app = XCUIApplication()
        app.launch()
        let aStatus = app.staticTexts["intent-fixture.a.management-status"]
        XCTAssertTrue(aStatus.waitForExistence(timeout: 10))
        let bStatus = app.staticTexts["intent-fixture.b.management-status"]
        XCTAssertTrue(bStatus.waitForExistence(timeout: 10))
        if bStatus.label != "enabled" {
            app.buttons["intent-fixture.b.enable"].tap()
            XCTAssertTrue(wait(for: "enabled", in: bStatus))
        }
        if aStatus.label != "enabled" {
            app.buttons["intent-fixture.a.enable"].tap()
            XCTAssertTrue(wait(for: "enabled", in: aStatus))
        }

        app.buttons["intent-fixture.a.disable"].tap()
        XCTAssertTrue(wait(for: "disabled", in: aStatus))
        app.terminate()
        app.launch()

        let relaunchedAStatus = app.staticTexts["intent-fixture.a.management-status"]
        let relaunchedBStatus = app.staticTexts["intent-fixture.b.management-status"]
        XCTAssertTrue(relaunchedAStatus.waitForExistence(timeout: 10))
        XCTAssertTrue(relaunchedBStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(relaunchedAStatus.label, "disabled")
        XCTAssertEqual(relaunchedBStatus.label, "enabled")

        app.buttons["Open Feature B"].tap()
        XCTAssertTrue(app.staticTexts["intent-fixture.b.value"].waitForExistence(timeout: 5))
        app.buttons["Add 1"].tap()
        XCTAssertTrue(app.staticTexts["completed"].waitForExistence(timeout: 5))
    }

    private func wait(for label: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
