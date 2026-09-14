import XCTest

@MainActor
final class P1WebUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    private let owners = ["p1-web-a", "p1-web-b"]

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        openManagement()
        for owner in owners { enableIfNeeded(owner) }
        closeManagement()
    }

    func testRealPageStorageSurvivesRestartAndRemovingAOnlyPreservesB() throws {
        for owner in owners {
            try open(owner)
            tap("p1.web.write")
            expectResult("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            tap("p1.web.write-fail")
            expectResultPrefix("failed:")
            tap("p1.web.read")
            expectResult("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            backToList()
        }
        backgroundTerminateAndLaunch()
        try open("p1-web-a")
        tap("p1.web.read")
        expectResult("local=p1-web-a cookie=p1-web-a indexeddb=p1-web-a")
        backToList()

        openManagement()
        tapManagement("management.delete.p1-web-a")
        XCTAssertTrue(app.alerts.buttons["キャンセル"].waitForExistence(timeout: 5))
        app.alerts.buttons["キャンセル"].tap()
        tapManagement("management.delete.p1-web-a")
        app.alerts.buttons["削除"].tap()
        expectManagement("p1-web-a", "削除済み", timeout: 20)
        closeManagement()

        try open("p1-web-b")
        tap("p1.web.read")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
        openManagement()
        enableIfNeeded("p1-web-a")
        expectManagement("p1-web-a", "有効")
        closeManagement()
        try open("p1-web-a")
        tap("p1.web.read")
        expectResult("local=missing cookie=missing indexeddb=missing")
        backToList()
    }

    func testExplicitHeldWriterCancelsWithoutCommittingAndBRemainsUsable() throws {
        try open("p1-web-a")
        tap("p1.web.write-delayed")
        expectResult("write waiting")
        tap("p1.web.cancel-write")
        expectResult("cancelled")
        tap("p1.web.read")
        expectResult("local=missing cookie=missing indexeddb=missing")
        backToList()
        try open("p1-web-b")
        tap("p1.web.write")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
    }

    func testManagementDrainsHeldWriterBeforeDeletingAAndPreservesB() throws {
        try open("p1-web-b")
        tap("p1.web.write")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
        try open("p1-web-a")
        tap("p1.web.write-delayed")
        expectResult("write waiting")
        backToList()
        openManagement()
        tapManagement("management.delete.p1-web-a")
        app.alerts.buttons["削除"].tap()
        expectManagement("p1-web-a", "削除済み", timeout: 20)
        closeManagement()
        openManagement()
        enableIfNeeded("p1-web-a")
        closeManagement()
        try open("p1-web-a")
        expectResult("cancelled")
        tap("p1.web.read")
        expectResult("local=missing cookie=missing indexeddb=missing")
        backToList()
        try open("p1-web-b")
        tap("p1.web.read")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
    }

    func testDisableRejectsDeepLinkWhileBRemainsUsable() throws {
        openManagement()
        tapManagement("management.disable.p1-web-a")
        expectManagement("p1-web-a", "無効（データを保持）")
        closeManagement()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p1-web-a")))
        XCTAssertFalse(app.staticTexts["p1.web.page"].waitForExistence(timeout: 3), app.debugDescription)
        openManagement()
        expectManagement("p1-web-a", "無効（データを保持）")
        closeManagement()
        try open("p1-web-b")
        tap("p1.web.write")
        expectResult("local=p1-web-b cookie=p1-web-b indexeddb=p1-web-b")
        backToList()
        openManagement()
        enableIfNeeded("p1-web-a")
        closeManagement()
    }

    private func open(_ owner: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + owner)))
        expectText(identifier: "p1.web.page", label: "page-ready", timeout: 20)
    }

    private func openManagement() { tap("management.open") }
    private func closeManagement() { tap("閉じる") }

    private func enableIfNeeded(_ owner: String) {
        let enable = managementButton("management.enable." + owner)
        if enable.exists { enable.tap(); expectManagement(owner, "有効") }
    }

    private func tapManagement(_ identifier: String) {
        let button = managementButton(identifier)
        XCTAssertTrue(button.exists && button.isHittable, app.debugDescription)
        button.tap()
    }

    private func managementButton(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<12 {
            if button.exists && button.isHittable { return button }
            app.swipeUp()
        }
        return button
    }

    private func expectManagement(_ owner: String, _ value: String, timeout: TimeInterval = 15) {
        expectText(identifier: "management.status." + owner, label: value, timeout: timeout)
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }

    private func expectResult(_ value: String) { expectText(identifier: "p1.web.result", label: value, timeout: 15) }

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

    private func backToList() { tap("miniapp.back-to-list") }

    private func backgroundTerminateAndLaunch() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
        app.terminate()
        app.launch()
    }
}
