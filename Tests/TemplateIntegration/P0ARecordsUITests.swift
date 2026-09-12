import XCTest

@MainActor
final class P0ARecordsUITests: XCTestCase {
    func testRecordsHostMaintenanceRestoresAttachmentsAndPreservesOtherOwner() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let row = app.buttons["miniapp.p0-records"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        app.buttons["p0.records.run"].tap()
        let result = app.staticTexts["p0.records.result"]
        let expected = "schema=2;failed-kept=Changed;restored=Legacy;attachment=3;reset=0;b=Other;generations=5/1"
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "P0-A-records-migration-restore-reset"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
