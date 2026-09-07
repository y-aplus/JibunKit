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

    private func enter(_ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        tap(field)
        let existing = field.value as? String ?? ""
        if !existing.isEmpty && existing != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(text)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func setPause(_ enabled: Bool) {
        let control = app.switches["全体停止"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        // SwiftUI exposes the whole Form row as a switch; its centre can be
        // the inert label area. Tap the visible switch at the trailing edge.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let expected = enabled ? "1" : "0"
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.value as? String, expected)
    }

    private func returnToList() {
        tap(app.navigationBars.buttons["ミニアプリ"])
        XCTAssertTrue(app.buttons["miniapp.zaiko"].waitForExistence(timeout: 5))
    }

    func testMigrationOperationsAndHostIntegration() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        capture("01-mini-app-list")

        tap(app.buttons["miniapp.counter"])
        tap(app.buttons["1を追加"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        let counterValue = app.staticTexts["counter.value"].label
        XCTAssertNotEqual(counterValue, "0")
        returnToList()

        tap(app.buttons["miniapp.zaiko"])
        XCTAssertEqual(app.navigationBars.count, 1, "Only the host owns root navigation")
        XCTAssertTrue(app.navigationBars["在庫管理"].exists)
        tap(app.buttons["zaiko.add"])
        tap(app.navigationBars.buttons["保存"])
        XCTAssertTrue(app.staticTexts["名前を入力してください。"].waitForExistence(timeout: 5))
        enter("zaiko.editor.name", "Rice")
        enter("zaiko.editor.category", "Food")
        enter("zaiko.editor.unit", "kg")
        enter("zaiko.editor.stock", "10")
        enter("zaiko.editor.speed", "2")
        tap(app.navigationBars.buttons["保存"])
        XCTAssertTrue(app.staticTexts["Rice"].waitForExistence(timeout: 5))
        tap(app.buttons["Food"])
        XCTAssertTrue(app.staticTexts["Rice"].exists)
        tap(app.buttons["すべて"])
        capture("02-created-inventory")

        tap(app.buttons["補充"])
        tap(app.textFields["補充前残量"])
        app.textFields["補充前残量"].typeText("8")
        tap(app.textFields["補充量"])
        app.textFields["補充量"].typeText("4")
        tap(app.navigationBars.buttons["保存"])
        XCTAssertTrue(app.staticTexts["Rice"].waitForExistence(timeout: 5))
        tap(app.buttons["編集モードへ"])
        tap(app.buttons["編集"])
        enter("zaiko.editor.name", "Rice Edited")
        tap(app.navigationBars.buttons["更新"])
        XCTAssertTrue(app.staticTexts["Rice Edited"].waitForExistence(timeout: 5))

        tap(app.buttons["zaiko.settings"])
        setPause(true)
        tap(app.buttons["閉じる"])
        XCTAssertTrue(app.staticTexts["全体停止中"].waitForExistence(timeout: 5))
        capture("03-paused-inventory")
        tap(app.buttons["zaiko.settings"])
        setPause(false)
        tap(app.buttons["閉じる"])
        XCTAssertFalse(app.staticTexts["全体停止中"].exists)

        // File flows must open after settings dismissal, without a second modal
        // trying to present on top of the closing settings sheet.
        tap(app.buttons["zaiko.settings"])
        tap(app.buttons["JSONバックアップを書き出す"])
        XCTAssertTrue(app.buttons["キャンセル"].waitForExistence(timeout: 10))
        capture("04-backup-export-picker")
        tap(app.buttons["キャンセル"])
        tap(app.buttons["zaiko.settings"])
        tap(app.buttons["JSONバックアップを読み込む"])
        XCTAssertTrue(app.buttons["キャンセル"].waitForExistence(timeout: 10))
        capture("05-backup-import-picker")
        tap(app.buttons["キャンセル"])

        // State must survive leaving the Feature and a full process restart.
        returnToList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        returnToList()
        app.terminate()
        app.launch()
        tap(app.buttons["miniapp.zaiko"])
        XCTAssertTrue(app.staticTexts["Rice Edited"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 1)
        capture("06-restored-inventory")
        tap(app.buttons["編集モードへ"])
        tap(app.buttons["削除"])
        tap(app.buttons["キャンセル"])
        XCTAssertTrue(app.staticTexts["Rice Edited"].exists)
        tap(app.buttons["削除"])
        tap(app.sheets.buttons["削除"])
        XCTAssertTrue(app.staticTexts["まだ在庫がありません"].waitForExistence(timeout: 5))
        returnToList()

        tap(app.buttons["miniapp.reminder"])
        tap(app.textFields["例: 水を飲む"])
        app.textFields["例: 水を飲む"].typeText("Migration reminder")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        returnToList()
        tap(app.buttons["miniapp.reminder"])
        XCTAssertEqual(app.textFields["例: 水を飲む"].value as? String, "Migration reminder")
        capture("07-reminder-independent-save")
    }
}
