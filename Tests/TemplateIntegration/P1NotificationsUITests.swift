import XCTest

@MainActor
final class P1NotificationsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    private let a = "p1-notification-a", b = "p1-notification-b"

    func testNativeAttachmentFailureCancellationAndManagementPreserveOtherOwner() throws {
        try prepare()
        for owner in [a, b] {
            try open(owner)
            tap("p1.notification.pending")
            result("registered pending")
            inventory(pending: 1, original: true)
        }
        try open(a)
        tap("p1.notification.fail")
        expect("p1.notification.result", begins: "failed:")
        inventory(pending: 1, original: true)
        tap("p1.notification.held")
        result("prepared waiting")
        tap("p1.notification.cancel")
        result("cancelled")
        inventory(pending: 1, original: true)
        app.terminate()
        app.launch()
        try open(a)
        inventory(pending: 1, original: true)
        try open(b)
        inventory(pending: 1, original: true)

        // The normal manager itself cancels/drains a copy still held by A.
        try open(a)
        tap("p1.notification.held")
        result("prepared waiting")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.disable." + a)
        status(a, "無効（データを保持）")
        tap("閉じる")
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + a)))
        XCTAssertTrue(app.buttons["management.open"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["p1.notification.inventory"].exists)
        try open(b)
        inventory(pending: 1, original: true)
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.enable." + a)
        status(a, "有効")
        tap("閉じる")
        try open(a)
        result("cancelled")
        inventory(pending: 0, original: true)
        tap("p1.notification.pending")
        result("registered pending")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.delete." + a)
        tapAlert("キャンセル")
        status(a, "有効")
        tap("management.delete." + a)
        tapAlert("削除")
        status(a, "削除済み")
        tap("management.enable." + a)
        status(a, "有効")
        tap("閉じる")
        try open(a)
        inventory(pending: 0, original: false)
        try open(b)
        inventory(pending: 1, original: true)
        tap("p1.notification.clear")
        result("requests cleared")
    }

    func testForegroundDeliveryConsultsOnlyItsNormalDefinition() throws {
        try prepare()
        try open(b)
        let beforeB = app.staticTexts["p1.notification.foreground"].label
        try open(a)
        tap("p1.notification.deliver")
        result("registered delivery")
        expect("p1.notification.foreground", begins: a + " policy=silent", timeout: 25)
        try open(b)
        tap("p1.notification.read")
        result("read")
        XCTAssertEqual(app.staticTexts["p1.notification.foreground"].label, beforeB)
        tap("p1.notification.deliver")
        result("registered delivery")
        expect("p1.notification.foreground", begins: b + " policy=banner", timeout: 25)
        tap("p1.notification.clear")
        result("requests cleared")
        try open(a)
        expect("p1.notification.foreground", begins: a + " policy=silent")
        tap("p1.notification.clear")
        result("requests cleared")
    }

    private func prepare() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        // Normal persisted management state is reset through normal actions.
        tap("management.open")
        for owner in [a, b] {
            let value = app.staticTexts["management.status." + owner]
            reveal(value)
            XCTAssertTrue(value.exists, app.debugDescription)
            if value.label != "有効" {
                tap("management.enable." + owner)
                status(owner, "有効")
            }
        }
        tap("閉じる")
        for owner in [a, b] {
            try open(owner)
            tap("p1.notification.authorize")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            result("authorized")
            tap("p1.notification.clear")
            result("requests cleared")
            tap("p1.notification.clear-events")
            result("events cleared")
            tap("p1.notification.read")
            result("read")
        }
    }

    private func open(_ owner: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + owner)))
        XCTAssertTrue(app.navigationBars[owner].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["p1.notification.result"].waitForExistence(timeout: 15))
    }
    private func reveal(_ element: XCUIElement, downFirst: Bool = false) {
        if element.exists && element.isHittable { return }
        for _ in 0..<12 {
            if downFirst { app.swipeDown() } else { app.swipeUp() }
            if element.exists && element.isHittable { return }
        }
        for _ in 0..<12 {
            if downFirst { app.swipeUp() } else { app.swipeDown() }
            if element.exists && element.isHittable { return }
        }
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        reveal(button)
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
    }
    private func tapAlert(_ title: String) {
        let button = app.alerts.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }
    private func status(_ owner: String, _ label: String) {
        let value = app.staticTexts["management.status." + owner]
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 60), .completed, app.debugDescription)
    }
    private func result(_ label: String) { expect("p1.notification.result", equals: label) }
    private func inventory(pending: Int, original: Bool) {
        tap("p1.notification.read")
        result("read")
        expect("p1.notification.inventory", equals:
            "pending=\(pending) readable=\(pending) matching=\(pending) delivered=0 original=\(original) staging=0")
    }
    private func expect(_ id: String, equals: String? = nil, begins: String? = nil, timeout: TimeInterval = 15) {
        reveal(app.staticTexts[id], downFirst: true)
        let predicate = equals.map { NSPredicate(format: "label == %@", $0) }
            ?? NSPredicate(format: "label BEGINSWITH %@", begins!)
        let match = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
}
