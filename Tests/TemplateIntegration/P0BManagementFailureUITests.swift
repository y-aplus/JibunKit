import XCTest

/// Copied only into the isolated signed CI host by the integration workflow.
@MainActor
final class P0BManagementFailureUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws { continueAfterFailure = false }

    func testUnregisterFailurePreservesDataThenRetryRemovesAndReregistersWithoutChangingCounter() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        // Establish a value owned by an unrelated production Feature.
        openFeature("counter")
        let counterValue = app.staticTexts["counter.value"]
        XCTAssertTrue(counterValue.waitForExistence(timeout: 10), app.debugDescription)
        let counterBefore = counterValue.label
        tap(app.buttons["1を追加"])
        let counterChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", counterBefore), object: counterValue)
        XCTAssertEqual(XCTWaiter.wait(for: [counterChanged], timeout: 10), .completed, app.debugDescription)
        let preservedCounter = counterValue.label
        tap(app.buttons["miniapp.back-to-list"])

        // URL entry avoids assuming that a long lazy launcher materialized the row.
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p0b-removal-failure")))
        let probeValue = app.staticTexts["p0b.failure.value"]
        XCTAssertTrue(probeValue.waitForExistence(timeout: 15), app.debugDescription)
        tap(app.buttons["p0b.failure.increment"])
        let savedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "saved="),
            object: app.staticTexts["p0b.failure.result"])
        XCTAssertEqual(XCTWaiter.wait(for: [savedExpectation], timeout: 10), .completed, app.debugDescription)
        let saved = probeValue.label
        tap(app.buttons["miniapp.back-to-list"])

        tap(app.buttons["management.open"])
        let delete = app.buttons["management.delete.p0b-removal-failure"]
        reveal(delete)
        tap(delete)
        let confirmation = app.alerts["所有データを削除しますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(confirmation.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "削除失敗診断: 診断用に保存したカウンター値")
        ).firstMatch.exists)
        tap(confirmation.buttons["削除"])

        let failureAlert = app.alerts["処理を完了できません"]
        XCTAssertTrue(failureAlert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(failureAlert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "saved=\(saved)")
        ).firstMatch.exists, failureAlert.debugDescription)
        tap(failureAlert.buttons["閉じる"])
        expectStatus("削除が未完了。再試行で残りの処理を完了してください。")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "登録解除で失敗しました。diagnostic unregister failed once; saved=\(saved)")
        ).firstMatch.exists, app.debugDescription)

        // The same action is now explicitly a retry; data deletion happens only here.
        reveal(delete)
        XCTAssertEqual(delete.label, "削除を再試行")
        tap(delete)
        tap(app.alerts["所有データを削除しますか？"].buttons["削除"])
        expectStatus("削除済み")
        let enable = app.buttons["management.enable.p0b-removal-failure"]
        reveal(enable)
        tap(enable)
        expectStatus("有効")
        tap(app.buttons["閉じる"])

        openFeature("p0b-removal-failure")
        XCTAssertTrue(probeValue.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(probeValue.label, "0")
        tap(app.buttons["miniapp.back-to-list"])
        openFeature("counter")
        XCTAssertTrue(counterValue.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(counterValue.label, preservedCounter)
    }

    private func openFeature(_ id: String) {
        let row = app.buttons["miniapp.\(id)"]
        reveal(row)
        tap(row)
    }

    private func reveal(_ element: XCUIElement) {
        if element.exists && element.isHittable { return }
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<10 {
            list.swipeDown()
            if element.exists && element.isHittable { return }
        }
        for _ in 0..<24 {
            list.swipeUp()
            if element.exists && element.isHittable { return }
        }
        XCTFail("Could not reveal \(element.debugDescription)\n\(app.debugDescription)")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, element.debugDescription, file: file, line: line)
        element.tap()
    }

    private func expectStatus(_ value: String) {
        let status = app.staticTexts["management.status.p0b-removal-failure"]
        reveal(status)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", value), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }
}
