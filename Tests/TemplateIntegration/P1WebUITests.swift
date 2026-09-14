import XCTest

@MainActor
final class P1WebUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
    }

    func testRealPageStorageSurvivesRestartAndRemovingAOnlyPreservesB() {
        for owner in ["p1-web-a", "p1-web-b"] {
            open(owner)
            tap("p1.web.write")
            expectResult("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            tap("p1.web.write-fail")
            expectResultPrefix("failed:")
            tap("p1.web.read")
            expectResult("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            backToList()
        }
        backgroundTerminateAndLaunch()
        open("p1-web-a")
        tap("p1.web.read")
        expectResult("local=p1-web-a cookie=p1-web-a indexeddb=p1-web-a")
        backToList()

        tap("management.open")
        tap("management.delete.p1-web-a")
        XCTAssertTrue(app.alerts.buttons["キャンセル"].waitForExistence(timeout: 5))
        app.alerts.buttons["キャンセル"].tap()
        tap("management.delete.p1-web-a")
        app.alerts.buttons["削除"].tap()
        expectText(identifier: "management.status.p1-web-a", label: "削除済み", timeout: 20)
        app.navigationBars.buttons["閉じる"].tap()

        open("p1-web-b")
        tap("p1.web.read")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
        tap("management.open")
        tap("management.enable.p1-web-a")
        expectText(identifier: "management.status.p1-web-a", label: "有効", timeout: 15)
        app.navigationBars.buttons["閉じる"].tap()
        open("p1-web-a")
        tap("p1.web.read")
        expectResult("local=missing cookie=missing indexeddb=missing")
    }

    func testCancellingDelayedWriterAllowsDisableAndBRemainsUsable() {
        open("p1-web-a")
        tap("p1.web.write-delayed")
        expectResult("write waiting")
        tap("p1.web.cancel-write")
        expectResult("cancelled")
        backToList()
        tap("management.open")
        tap("management.disable.p1-web-a")
        expectText(identifier: "management.status.p1-web-a", label: "無効（データを保持）", timeout: 20)
        app.navigationBars.buttons["閉じる"].tap()
        XCTAssertFalse(app.buttons["miniapp.p1-web-a"].isEnabled)
        open("p1-web-b")
        tap("p1.web.write")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
        tap("management.open")
        tap("management.enable.p1-web-a")
        expectText(identifier: "management.status.p1-web-a", label: "有効", timeout: 15)
    }

    /// Requires the parent-owned management ordering change recorded in the submission:
    /// close admission, stop/drain the lifetime, then acquire the deletion reservation.
    func testManagementStopsInFlightWriterBeforeOwnerDeletion() {
        open("p1-web-a")
        tap("p1.web.write-delayed")
        expectResult("write waiting")
        backToList()
        tap("management.open")
        tap("management.delete.p1-web-a")
        app.alerts.buttons["削除"].tap()
        expectText(identifier: "management.status.p1-web-a", label: "削除済み", timeout: 20)
        app.navigationBars.buttons["閉じる"].tap()
        tap("management.open")
        tap("management.enable.p1-web-a")
        expectText(identifier: "management.status.p1-web-a", label: "有効", timeout: 15)
        app.navigationBars.buttons["閉じる"].tap()
        open("p1-web-a")
        tap("p1.web.read")
        expectResult("local=missing cookie=missing indexeddb=missing")
    }

    private func open(_ owner: String) {
        let direct = app.buttons["miniapp.\(owner)"]
        if direct.waitForExistence(timeout: 2) { direct.tap() }
        else {
            tap("miniapp.switch.open")
            tap("miniapp.switch.\(owner)")
        }
        expectText(identifier: "p1.web.page", label: "page-ready", timeout: 20)
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }

    private func expectResult(_ value: String) {
        expectText(identifier: "p1.web.result", label: value, timeout: 15)
    }

    private func expectResultPrefix(_ value: String) {
        let element = app.staticTexts.matching(identifier: "p1.web.result")
            .matching(NSPredicate(format: "label BEGINSWITH %@", value)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
    }

    private func expectText(identifier: String, label: String, timeout: TimeInterval) {
        let element = app.staticTexts.matching(identifier: identifier)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), app.debugDescription)
    }

    private func backToList() {
        let back = app.navigationBars.buttons["ミニアプリ"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), app.debugDescription)
        back.tap()
    }

    private func backgroundTerminateAndLaunch() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
        app.terminate()
        app.launch()
    }
}
