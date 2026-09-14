import Foundation
import XCTest

@MainActor
final class P1HTTPUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    private var port: String { ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] ?? "" }

    func testRealHTTPPersistenceFailuresDrainLogoutRemovalAndOtherOwnerRetention() throws {
        continueAfterFailure = false
        XCTAssertFalse(port.isEmpty, "Runner must receive JIBUNKIT_NETWORK_TEST_PORT")
        launch()
        try normalizeEnabled("p1-http-a")
        try normalizeEnabled("p1-http-b")

        try open("p1-http-a")
        tap("p1.http.login")
        expect("p1.http.status", "completed login")
        expect("p1.http.cookie", "account=p1-http-a-stable")
        expect("p1.http.auth", authorization(password: "owner-a-stable"))
        expect("p1.http.cache", "p1-http-a-stable")
        tap("p1.http.reload")
        expect("p1.http.status", "completed reload")
        expect("p1.http.cache", "p1-http-a-stable")
        tap("miniapp.back-to-list")

        try open("p1-http-b")
        tap("p1.http.login")
        expect("p1.http.status", "completed login")
        expect("p1.http.cookie", "account=p1-http-b-stable")
        expect("p1.http.auth", authorization(password: "owner-b-stable"))
        tap("miniapp.back-to-list")

        // Persistent credentials/cookies are reloaded after process recreation.
        // Cache is intentionally not asserted here: URLCache process persistence is OS policy.
        app.terminate(); launch()
        try open("p1-http-a")
        tap("p1.http.reload")
        expect("p1.http.status", "completed reload")
        expect("p1.http.cookie", "account=p1-http-a-stable")
        expect("p1.http.auth", authorization(password: "owner-a-stable"))

        tap("p1.http.fail-save")
        expect("p1.http.status", "precommit failure armed")
        tap("p1.http.login")
        expectContains("p1.http.status", "old durable snapshots restored")
        expect("p1.http.cookie", "account=p1-http-a-stable")
        expect("p1.http.auth", authorization(password: "owner-a-stable"))
        tap("p1.http.fail-connect")
        expectContains("p1.http.status", "expected unauthenticated HTTP failure")
        expect("p1.http.cookie", "account=p1-http-a-stable")

        tap("p1.http.hold")
        expect("p1.http.status", "writer started")
        tap("p1.http.cancel")
        expect("p1.http.status", "cancelled held-write; no late cookie", timeout: 30)
        expect("p1.http.cookie", "account=p1-http-a-stable")

        // This time logout drains a request that has demonstrably reached the fixture.
        tap("p1.http.hold")
        expect("p1.http.status", "writer started")
        tap("p1.http.logout")
        let resume = app.buttons["miniapp.start.resume"]
        reveal(resume)
        tap(resume)
        reveal(app.buttons["p1.http.reload"])
        expect("p1.http.status", "logout completed; reopen to inspect", timeout: 30)
        tap("p1.http.reload")
        expect("p1.http.status", "completed reload")
        expect("p1.http.cookie", "")
        expect("p1.http.auth", "unauthenticated")

        tap("miniapp.back-to-list")
        tap("management.open")
        status("p1-http-a", equals: "有効")
        tap("management.disable.p1-http-a")
        status("p1-http-a", equals: "無効（データを保持）")
        tap("閉じる")
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p1-http-a")))
        XCTAssertFalse(app.staticTexts["p1.http.status"].waitForExistence(timeout: 3), "disabled A deep link must be rejected")

        tap("management.open")
        status("p1-http-a", equals: "無効（データを保持）")
        tap("management.delete.p1-http-a")
        XCTAssertTrue(app.alerts.buttons["削除"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        tap("management.delete.p1-http-a")
        app.alerts.buttons["削除"].tap()
        status("p1-http-a", equals: "削除済み", timeout: 60)
        tap("management.enable.p1-http-a")
        status("p1-http-a", equals: "有効")
        tap("閉じる")
        try open("p1-http-a")
        tap("p1.http.reload")
        expect("p1.http.status", "completed reload")
        expect("p1.http.cookie", "")
        expect("p1.http.auth", "unauthenticated")
        tap("miniapp.back-to-list")
        try open("p1-http-b")
        tap("p1.http.reload")
        expect("p1.http.status", "completed reload")
        expect("p1.http.cookie", "account=p1-http-b-stable")
        expect("p1.http.auth", authorization(password: "owner-b-stable"))
    }

    private func launch() {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment = ["JIBUNKIT_NETWORK_TEST_PORT": port]
        app.launch()
    }
    private func authorization(password: String) -> String {
        "Basic " + Data(("account:" + password).utf8).base64EncodedString()
    }
    private func normalizeEnabled(_ owner: String) throws {
        tap("management.open")
        let state = status(owner)
        if state != "有効" { tap("management.enable." + owner); status(owner, equals: "有効") }
        tap("閉じる")
    }
    private func open(_ owner: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + owner)))
        let title = app.navigationBars[owner]
        reveal(title)
        XCTAssertTrue(title.exists, "requested owner navigation did not open: \(app.debugDescription)")
        reveal(app.staticTexts["p1.http.status"])
    }
    private func status(_ owner: String, equals expected: String, timeout: TimeInterval = 15) { expect("management.status." + owner, expected, timeout: timeout) }
    @discardableResult private func status(_ owner: String) -> String { let element = app.staticTexts["management.status." + owner]; reveal(element); return element.label }
    private func tap(_ id: String) { tap(app.buttons[id]) }
    private func tap(_ button: XCUIElement) { reveal(button); XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap() }
    private func reveal(_ element: XCUIElement) {
        if element.exists && element.isHittable { return }
        for _ in 0..<6 { app.swipeUp(); if element.exists && element.isHittable { return } }
        for _ in 0..<12 { app.swipeDown(); if element.exists && element.isHittable { return } }
        for _ in 0..<6 { app.swipeUp(); if element.exists && element.isHittable { return } }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func expect(_ id: String, _ value: String, timeout: TimeInterval = 15) {
        let element = app.staticTexts[id]; reveal(element)
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
    private func expectContains(_ id: String, _ value: String, timeout: TimeInterval = 15) {
        let element = app.staticTexts[id]; reveal(element)
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
}
