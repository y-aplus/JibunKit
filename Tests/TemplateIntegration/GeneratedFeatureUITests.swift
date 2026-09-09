import XCTest

/// Copied only into the temporary Notes-integrated host by CI.
@MainActor
final class GeneratedFeatureUITests: XCTestCase {
    func testSelectedRestoreStopsAndRestartsOnlyItsRuntime() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func status(_ value: String) {
            let text = app.staticTexts.matching(identifier: "lifecycle.task.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(owner)")
            tap("lifecycle.task.start")
            status("running")
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        tap("runtime.restore.open")
        let selection = app.switches["backup.restore.lifecycle-a"]
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap("backup.restore")
        app.alerts.buttons["置き換えて復元"].tap()
        XCTAssertTrue(app.staticTexts["lifecycle-aを復元しました。"].waitForExistence(timeout: 10), app.debugDescription)
        tap("閉じる")
        status("idle")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "restored")
        tap("lifecycle.task.start")
        status("running")
        tap("lifecycle.task.complete")
        status("completed")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        status("running")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "original")
        tap("lifecycle.task.complete")
        status("completed")
    }

    func testIdleTimerKeepsOtherFeaturesRequestActive() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "idle.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("idle.open")
        }
        func backToList() {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("idle.acquire")
            expect("disabled")
            backToList()
        }
        open("lifecycle-a")
        tap("idle.shutdown")
        expect("disabled")
        backToList()
        open("lifecycle-b")
        tap("idle.read")
        expect("disabled")
        tap("idle.shutdown")
        expect("enabled")
    }

    func testWebDataPersistsAndClearingPreservesOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "webdata.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
            print("WEB-PERSISTENCE expected=\(value) \(app.staticTexts["webdata.diagnostic"].label)")
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("webdata.open")
            XCTAssertTrue(app.staticTexts["page-ready"].waitForExistence(timeout: 15), app.debugDescription)
        }
        // Restart between owners also verifies native persistence, not in-memory state.
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("webdata.remove")
            expect("removed")
            tap("webdata.save")
            expect("saved")
            tap("webdata.read")
            expect(owner)
            // Exercise the normal background lifecycle before process recreation.
            // Abrupt termination immediately after setCookie is a separate durability case.
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.terminate()
            app.launch()
        }
        open("lifecycle-a")
        tap("webdata.read")
        expect("lifecycle-a")
        tap("webdata.remove")
        expect("removed")
        tap("webdata.read")
        expect("missing")
        app.terminate()
        app.launch()
        open("lifecycle-b")
        tap("webdata.read")
        expect("lifecycle-b")
        tap("webdata.remove")
        expect("removed")
    }

    func testKeychainPersistsAndLogoutPreservesOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "keychain.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("keychain.open")
        }
        // Restart between owners also verifies native persistence, not in-memory state.
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("keychain.remove")
            expect("removed")
            tap("keychain.save")
            expect("saved")
            app.terminate()
            app.launch()
        }
        open("lifecycle-a")
        tap("keychain.read")
        expect("lifecycle-a")
        tap("keychain.remove")
        expect("removed")
        tap("keychain.read")
        expect("missing")
        app.terminate()
        app.launch()
        open("lifecycle-b")
        tap("keychain.read")
        expect("lifecycle-b")
        tap("keychain.remove")
        expect("removed")
    }

    func testNativeCustomActionReachesOwnerWithoutReplacingVisibleFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        tap("miniapp.lifecycle-a")
        tap("notification.action.schedule")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["scheduled"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)))
        let card = springboard.buttons.matching(identifier: "ShortLook.Platter.Content.Seamless")
            .containing(.staticText, identifier: "Action-lifecycle-a").firstMatch
        let visible = card.waitForExistence(timeout: 20)
        let evidence = XCTAttachment(screenshot: springboard.screenshot())
        evidence.name = "custom-action-notification-center"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard visible else {
            XCTFail("Action notification missing: \(springboard.debugDescription)")
            return
        }
        card.swipeLeft()
        let view = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["View", "表示"])).firstMatch
        guard view.waitForExistence(timeout: 5) else {
            let evidence = XCTAttachment(screenshot: springboard.screenshot())
            evidence.name = "custom-action-swiped"
            evidence.lifetime = .keepAlways
            add(evidence)
            XCTFail("Notification View action unavailable: \(springboard.debugDescription)")
            return
        }
        view.tap()
        let expanded = XCTAttachment(screenshot: springboard.screenshot())
        expanded.name = "custom-action-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        let action = springboard.buttons["Action"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), springboard.debugDescription)
        action.tap()
        app.activate()
        XCTAssertTrue(app.navigationBars["lifecycle-b"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["notification.action.result"].label, "none")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-a")
        let result = app.staticTexts.matching(identifier: "notification.action.result")
            .matching(NSPredicate(format: "label == %@", "same-action")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testForegroundNotificationsConsultOnlyTheirOwner() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func count(_ value: String) {
            let text = app.staticTexts.matching(identifier: "notification.foreground.count")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 15), app.debugDescription)
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(owner)")
            count("0")
            tap("notification.schedule")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            count("1")
            // Do not leave B's list notification to group with the later action probe.
            tap("notification.clear")
            XCTAssertTrue(app.staticTexts["cleared"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        count("1")
    }

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
