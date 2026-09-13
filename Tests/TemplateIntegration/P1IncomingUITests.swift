import XCTest

/// The actual host inbox and two normal Definitions. OS share-sheet delivery
/// itself remains a device criterion; this does not substitute for that check.
@MainActor
final class P1IncomingUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    func testPersistentIncomingFailureRetryIsIdempotentAndOtherOwnerRemainsIndependent() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        try open("incoming-a")
        let count = app.staticTexts["p1.incoming.count"]
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        let beforeA = try XCTUnwrap(Int(count.label))
        tap("p1.incoming.fail")
        expect(app.staticTexts["p1.incoming.status"], "failure armed")
        tap("p1.incoming.seed")
        expect(app.staticTexts["p1.incoming.status"], "A/B queued")
        tap("miniapp.back-to-list")
        tap("incoming.open")
        tap("incoming.apply.incoming-a")
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "診断: 保存後の応答失敗"), object: app.staticTexts["incoming.message"])
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 15), .completed, app.debugDescription)

        // A committed before the injected response failure. Restart retains its
        // pending receipt; the stable ID prevents a second business commit.
        app.terminate()
        app.launch()
        tap("incoming.open")
        tap("incoming.apply.incoming-a")
        expect(app.staticTexts["incoming.message"], "取り込みました。")
        XCTAssertTrue(app.buttons["incoming.apply.incoming-b"].exists)
        tap("incoming.apply.incoming-b")
        let empty = app.staticTexts["未取込みの共有データはありません。"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["閉じる"].tap()
        try open("incoming-a")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        XCTAssertEqual(count.label, String(beforeA + 1))
        XCTAssertTrue(app.staticTexts["p1.incoming.contents"].label.contains("A incoming text"))
        tap("miniapp.back-to-list")
        try open("incoming-b")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        XCTAssertTrue(app.staticTexts["p1.incoming.contents"].label.contains("B incoming text"))
    }

    private func open(_ id: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + id)))
        XCTAssertTrue(app.staticTexts["p1.incoming.count"].waitForExistence(timeout: 15), app.debugDescription)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
    private func expect(_ element: XCUIElement, _ text: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 15), .completed, app.debugDescription)
    }
}
