import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    func testStandaloneFeatureLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["builder.repository"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["builder.build"].isEnabled)
    }
}
