import XCTest

@MainActor
final class WebStorageOwnershipUITests: XCTestCase {
    /// Diagnostic comparison, not a claim that native setCookie flushes to disk.
    /// The existing strict persistence regression remains a separate test.
    func testNativeCookiePersistenceMatchesDefaultAtControlledTerminationIntervals() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        func tap(_ identifier: String) {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
            button.tap()
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("webdata.open")
            XCTAssertTrue(app.staticTexts["page-ready"].waitForExistence(timeout: 20), app.debugDescription)
        }
        func expect(_ identifier: String, _ value: String) {
            let text = app.staticTexts.matching(identifier: identifier)
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        for interval in [TimeInterval(0), 5, 15] {
            for owner in ["lifecycle-a", "lifecycle-b"] {
                // A fresh value prevents an earlier trial's disk data from
                // appearing to prove this trial was persisted.
                let value = owner + "-" + UUID().uuidString
                app.launchEnvironment["JIBUNKIT_WEB_COOKIE_VALUE"] = value
                app.launch()
                open(owner)
                tap("webdata.remove")
                expect("webdata.result", "removed")
                tap("webdata.save")
                expect("webdata.result", "saved")
                tap("webdata.read")
                expect("webdata.result", value)
                expect("webdata.baseline", value)
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
                // This fixed interval is the experimental variable, not a
                // retry or a production workaround for native flushing.
                if interval > 0 { Thread.sleep(forTimeInterval: interval) }
                app.terminate()
                app.launch()
                open(owner)
                tap("webdata.read")
                let read = app.staticTexts.matching(identifier: "webdata.result")
                    .matching(NSPredicate(format: "label != %@", "unread")).firstMatch
                XCTAssertTrue(read.waitForExistence(timeout: 10), app.debugDescription)
                let profile = app.staticTexts["webdata.result"].label
                let baseline = app.staticTexts["webdata.baseline"].label
                print("WEB-COOKIE-COMPARISON owner=\(owner) backgroundInterval=\(interval) expected=\(value) profile=\(profile) baseline=\(baseline)")
                XCTAssertEqual(profile, baseline, "Identified/default persistence differs at interval \(interval)")
                XCTAssertTrue(profile == value || profile == "missing", "Stale cookie from a previous trial: \(profile)")
                app.terminate()
            }
        }
    }

    func testPageStorageSurvivesBackgroundRestartAndOwnerClearPreservesOther() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

        func launch() {
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        }
        func tap(_ identifier: String) {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
            button.tap()
        }
        func open(_ owner: String) {
            let listButton = app.buttons["miniapp.\(owner)"]
            if listButton.waitForExistence(timeout: 2) {
                listButton.tap()
            } else {
                tap("miniapp.switch.open")
                tap("miniapp.switch.\(owner)")
            }
            let ready = app.staticTexts.matching(identifier: "web-storage.page")
                .matching(NSPredicate(format: "label == %@", "page-ready")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 20), app.debugDescription)
        }
        func expect(_ expected: String) {
            let result = app.staticTexts.matching(identifier: "web-storage.result")
                .matching(NSPredicate(format: "label == %@", expected)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
            print("WEB-STORAGE-OWNERSHIP \(expected)")
        }
        func clear(_ owner: String) {
            tap("web-storage.clear")
            expect("removed owner=\(owner)")
        }
        func writeAndObserve(_ owner: String) {
            tap("web-storage.write")
            expect("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            tap("web-storage.read")
            expect("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
        }
        func backgroundAndTerminate() {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
            app.terminate()
        }

        launch()
        for owner in ["web-storage-owner-a", "web-storage-owner-b"] {
            open(owner)
            clear(owner)
            writeAndObserve(owner)
        }

        backgroundAndTerminate()
        launch()
        open("web-storage-owner-a")
        tap("web-storage.read")
        expect("local=web-storage-owner-a cookie=web-storage-owner-a indexeddb=web-storage-owner-a")
        clear("web-storage-owner-a")
        tap("web-storage.read")
        expect("local=missing cookie=missing indexeddb=missing")

        backgroundAndTerminate()
        launch()
        open("web-storage-owner-b")
        tap("web-storage.read")
        expect("local=web-storage-owner-b cookie=web-storage-owner-b indexeddb=web-storage-owner-b")
        clear("web-storage-owner-b")
    }
}
