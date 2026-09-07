import XCTest

@MainActor
final class MigrationUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription, file: file, line: line)
        element.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func returnToList() {
        tap(app.navigationBars.buttons["ミニアプリ"])
        XCTAssertTrue(app.buttons["miniapp.counter"].waitForExistence(timeout: 5))
    }

    func testBackupRequiresSelectionAndOpensFileExporter() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        tap(app.buttons["backup.open"])
        let export = app.buttons["backup.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(export.isEnabled)
        let counter = app.switches["backup.export.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(export.isEnabled)
        tap(export)
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 20))
        capture("backup-file-exporter")
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["キャンセル", "Cancel"])).firstMatch
        tap(cancel)
        XCTAssertTrue(app.buttons["backup.import"].waitForExistence(timeout: 10))
        tap(app.buttons["閉じる"])
        XCTAssertTrue(app.buttons["miniapp.counter"].waitForExistence(timeout: 5))
    }

    func testPersistenceAndHostIntegration() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        capture("01-mini-app-list")

        tap(app.buttons["miniapp.counter"])
        tap(app.buttons["1を追加"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        let counterValue = app.staticTexts["counter.value"].label
        XCTAssertNotEqual(counterValue, "0")
        returnToList()

        tap(app.buttons["miniapp.reminder"])
        XCTAssertEqual(app.navigationBars.count, 1, "Only the host owns root navigation")
        let message = app.textFields["例: 水を飲む"]
        tap(message)
        let previous = message.value as? String ?? ""
        if !previous.isEmpty && previous != message.placeholderValue {
            message.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        message.typeText("Independent reminder")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        returnToList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        returnToList()
        app.terminate()
        app.launch()
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        returnToList()
        tap(app.buttons["miniapp.reminder"])
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.value as? String, "Independent reminder")
        capture("02-restored-independent-stores")
    }

    func testNotificationDeliveryAndRouting() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        tap(app.buttons["miniapp.reminder"])
        let message = app.textFields["例: 水を飲む"]
        tap(message)
        let previous = message.value as? String ?? ""
        if !previous.isEmpty && previous != message.placeholderValue {
            message.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        message.typeText("Migration reminder")
        tap(app.buttons["10秒後に通知"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["許可", "Allow"])
        ).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.staticTexts["10秒後の通知を予約しました"].waitForExistence(timeout: 5))
        returnToList()
        tap(app.buttons["miniapp.counter"])
        XCUIDevice.shared.press(.home)
        let notification = springboard.staticTexts["Migration reminder"].firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 20))
        let delivered = XCTAttachment(screenshot: springboard.screenshot())
        delivered.name = "08-delivered-notification"
        delivered.lifetime = .keepAlways
        add(delivered)
        notification.tap()
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["例: 水を飲む"].value as? String, "Migration reminder")
        capture("09-notification-routed-to-reminder")
    }

    func testStandaloneCounterUsesIndependentStorage() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        let original = app.staticTexts["counter.value"].label
        let standalone = XCUIApplication(bundleIdentifier: "com.jibunkit.counterexample")
        standalone.launchArguments = app.launchArguments
        standalone.launch()
        XCTAssertTrue(standalone.staticTexts["counter.value"].waitForExistence(timeout: 10))
        let before = standalone.staticTexts["counter.value"].label
        tap(standalone.buttons["1を追加"])
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before),
            object: standalone.staticTexts["counter.value"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let after = standalone.staticTexts["counter.value"].label
        standalone.terminate()
        standalone.launch()
        XCTAssertTrue(standalone.staticTexts["counter.value"].waitForExistence(timeout: 10))
        XCTAssertEqual(standalone.staticTexts["counter.value"].label, after)
        app.activate()
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["counter.value"].label, original)
    }
}
