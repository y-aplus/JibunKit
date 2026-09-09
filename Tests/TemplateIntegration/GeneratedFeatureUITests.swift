import XCTest

/// Copied only into the temporary Notes-integrated host by CI.
@MainActor
final class GeneratedFeatureUITests: XCTestCase {
    func testNativeCategoryUpdatesPreserveOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ identifiers: [String]) {
            let text = app.staticTexts.matching(identifier: "notification.categories")
                .matching(NSPredicate(format: "label == %@", identifiers.sorted().joined(separator: ","))).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        let a = "jibunkit.lifecycle-a.category.aW5pdGlhbA=="
        let b = "jibunkit.lifecycle-b.category.aW5pdGlhbA=="
        let updated = "jibunkit.lifecycle-a.category.dXBkYXRlZA=="
        tap("miniapp.lifecycle-a")
        tap("notification.read")
        expect([a, b])
        tap("notification.replace")
        expect([updated, b])
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        tap("notification.read")
        expect([updated, b])
        tap("notification.remove")
        expect([updated])
        app.terminate()
        app.launch()
        tap("miniapp.lifecycle-a")
        tap("notification.read")
        expect([a, b])
    }

    func testCancellingOneFeatureLeavesOtherFeatureTaskRunning() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func status(_ value: String) {
            let expected = app.staticTexts.matching(identifier: "lifecycle.task.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(expected.waitForExistence(timeout: 5))
        }
        for id in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(id)")
            tap("lifecycle.task.start")
            status("running")
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        tap("lifecycle.task.cancel")
        status("cancelled")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        status("running")
        tap("lifecycle.task.complete")
        status("completed")
    }

    func testUnopenedFeaturesReceiveHostBackgroundAndResume() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["miniapp.lifecycle-a"].waitForExistence(timeout: 10))
        // Neither Feature's root view has been created yet.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        var observed: [String] = []
        for id in ["lifecycle-a", "lifecycle-b"] {
            let entry = app.buttons["miniapp.\(id)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            entry.tap()
            let events = app.staticTexts["lifecycle.events"]
            XCTAssertTrue(events.waitForExistence(timeout: 5))
            let phases = events.label.split(separator: ",")
            XCTAssertTrue(phases.contains("background"))
            XCTAssertGreaterThanOrEqual(phases.filter { $0 == "active" }.count, 2)
            observed.append(events.label)
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        XCTAssertEqual(observed.first, observed.last)
    }

    func testRecordReminderSchedulingAndCancellation() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        tap(app.buttons["miniapp.records"])
        tap(app.buttons["records.add"])
        let title = "Notification-" + UUID().uuidString.prefix(8)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.buttons["records.save"])
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                            "records.row.", String(title))).firstMatch)
        app.swipeUp()
        tap(app.buttons["records.reminder.schedule"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["通知を予約しました。"].waitForExistence(timeout: 10))
        tap(app.buttons["records.reminder.cancel"])
        XCTAssertTrue(app.staticTexts["この記録の通知を取り消しました。"].waitForExistence(timeout: 10))
    }

    func testRecordsUsesIndependentHostStorage() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        tap(app.buttons["miniapp.counter"])
        let counterValue = app.staticTexts["counter.value"].label
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.records"])
        tap(app.buttons["records.add"])
        let title = "Hosted-" + UUID().uuidString.prefix(8)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText("Host record")
        tap(app.buttons["records.save"])
        app.terminate()
        app.launch()
        tap(app.buttons["miniapp.records"])
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let recordID = String(row.identifier.dropFirst("records.row.".count))
        XCTAssertNotNil(UUID(uuidString: recordID))
        tap(row)
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
        tap(app.navigationBars.buttons["記録"])
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=invalid")))
        XCTAssertTrue(app.staticTexts["counter.value"].exists)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=\(recordID)")))
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
    }

    func testGeneratedFeatureCoexistsAndRoutesInHost() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let notes = app.buttons["miniapp.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["miniapp.counter"].exists)
        XCTAssertTrue(app.buttons["miniapp.reminder"].exists)
        notes.tap()
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["ミニアプリ"].tap()
        let counter = app.buttons["miniapp.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.tap()
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["counter.value"].exists)
        app.navigationBars.buttons["ミニアプリ"].tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
    }
}
