import XCTest

@MainActor
final class BackupRestoreUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.backup-harness")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchHarness() {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        expectValues("9|keep")
    }

    private func expectValues(_ value: String) {
        let predicate = NSPredicate(format: "label == %@", value)
        expectation(for: predicate, evaluatedWith: app.staticTexts["harness.values"])
        waitForExpectations(timeout: 10)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        element.tap()
    }

    private func select(_ id: String) {
        let toggle = app.switches["backup.restore.\(id)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    func testCancelThenRestoreOnlyCounterAndPersist() {
        launchHarness()
        tap(app.buttons["harness.valid"])
        XCTAssertFalse(app.buttons["backup.restore"].isEnabled)
        select("counter")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["キャンセル"])
        tap(app.buttons["閉じる"])
        expectValues("9|keep")
        tap(app.buttons["harness.valid"])
        select("counter")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["置き換えて復元"])
        XCTAssertTrue(app.staticTexts["カウンターを復元しました。"].waitForExistence(timeout: 10))
        tap(app.buttons["閉じる"])
        expectValues("3|keep")
        app.terminate()
        app.launchArguments.append("--preserve")
        app.launch()
        expectValues("3|keep")
    }

    func testRestoreOnlyReminderLeavesCounterUnchanged() {
        launchHarness()
        tap(app.buttons["harness.valid"])
        select("reminder")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["置き換えて復元"])
        XCTAssertTrue(app.staticTexts["リマインダーを復元しました。"].waitForExistence(timeout: 10))
        tap(app.buttons["閉じる"])
        expectValues("9|old")
    }

    func testInvalidSelectedPayloadPreservesBothStores() {
        launchHarness()
        tap(app.buttons["harness.invalid"])
        select("counter")
        select("reminder")
        tap(app.buttons["backup.restore"])
        let status = app.staticTexts["backup.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("保存データは変更していません"))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap(app.buttons["閉じる"])
        expectValues("9|keep")
    }

    func testApplyFailureReportsCompletedFeature() {
        launchHarness()
        tap(app.buttons["harness.failure"])
        select("counter")
        select("reminder")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["置き換えて復元"])
        let status = app.staticTexts["backup.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("完了済み: カウンター"))
        XCTAssertTrue(status.label.contains("リマインダーで失敗"))
        tap(app.buttons["閉じる"])
        expectValues("3|keep")
    }
}
