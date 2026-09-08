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
        if !element.isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: element)
        waitForExpectations(timeout: 10)
        element.tap()
    }

    private func select(_ id: String) {
        let toggle = app.switches["backup.restore.\(id)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if !toggle.isHittable { app.swipeUp() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
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

    func testFileBackupCancelThenRestoreOnlyAttachmentAndPersist() {
        launchHarness()
        XCTAssertEqual(app.staticTexts["harness.file-value"].label, "live attachment")
        tap(app.buttons["harness.files"])
        select("files")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["キャンセル"])
        tap(app.buttons["閉じる"])
        expectValues("9|keep")
        XCTAssertEqual(app.staticTexts["harness.file-value"].label, "live attachment")
        tap(app.buttons["harness.files"])
        select("files")
        tap(app.buttons["backup.restore"])
        tap(app.alerts.buttons["置き換えて復元"])
        XCTAssertTrue(app.staticTexts["添付テストを復元しました。"].waitForExistence(timeout: 10))
        tap(app.buttons["閉じる"])
        let predicate = NSPredicate(format: "label == %@", "restored attachment")
        expectation(for: predicate, evaluatedWith: app.staticTexts["harness.file-value"])
        waitForExpectations(timeout: 10)
        expectValues("9|keep")
        app.terminate()
        app.launchArguments.append("--preserve")
        app.launch()
        expectValues("9|keep")
        XCTAssertEqual(app.staticTexts["harness.file-value"].label, "restored attachment")
    }
}
