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

        let failureMessage = app.staticTexts["management.error"]
        reveal(failureMessage)
        XCTAssertTrue(failureMessage.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(failureMessage.label.contains("saved=\(saved)"), failureMessage.debugDescription)
        expectStatus("削除が未完了。再試行で残りの処理を完了してください。")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "通知・検索などの登録解除で失敗しました。diagnostic unregister failed once; saved=\(saved)")
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
        let managementList = app.collectionViews["management.list"]
        let inManagement = managementList.exists
        let list = inManagement ? managementList : app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)

        func positionMaterializedElement() -> Bool {
            guard element.exists else { return false }
            for _ in 0..<6 {
                guard element.exists else { return false }
                let frame = element.frame
                // The launcher's search field and navigation bar remain in
                // the hierarchy behind the sheet; neither bounds this List.
                let bar = inManagement ? app.navigationBars["ミニアプリの管理"] : app.navigationBars.firstMatch
                let top = bar.frame.maxY + 4
                let search = app.searchFields.firstMatch
                let bottom = !inManagement && search.exists && search.isHittable
                    ? search.frame.minY - 4 : list.frame.maxY - 30
                if frame.height > 0 && frame.minY >= top && frame.maxY <= bottom { return true }
                // Small directed movement avoids jumping past a short status
                // row and then sweeping away from it all the way to the end.
                let startY = frame.minY < top ? 0.40 : 0.75
                let endY = frame.minY < top ? 0.70 : 0.40
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05, thenDragTo:
                        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            }
            return false
        }
        if positionMaterializedElement() { return }
        for _ in 0..<10 {
            list.swipeDown()
            if positionMaterializedElement() { return }
        }
        for _ in 0..<24 {
            list.swipeUp()
            if positionMaterializedElement() { return }
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
