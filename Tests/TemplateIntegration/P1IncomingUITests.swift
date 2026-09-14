import XCTest

/// The actual host inbox and two normal Definitions. OS share-sheet delivery
/// itself remains a device criterion; this does not substitute for that check.
@MainActor
final class P1IncomingUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    func testOSShareTextURLAndFileReachInboxAndRetryWithoutDuplicateCommit() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        try open("incoming-b")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        let beforeB = app.staticTexts["p1.incoming.count"].label
        try open("incoming-a")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        let beforeA = try XCTUnwrap(Int(app.staticTexts["p1.incoming.count"].label))
        for (index, type) in ["text", "url", "file"].enumerated() {
            if index == 0 {
                tap("p1.incoming.fail")
                expect(app.staticTexts["p1.incoming.status"], "failure armed")
            }
            tap("p1.incoming.share." + type)
            let share = app.buttons.matching(NSPredicate(format: "label == %@", "JibunKit")).firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
            share.tap()
            let target = app.buttons["share.destination.incoming-a"]
            // On a provider/extension error the hierarchy includes share.error.
            // Stop the smoke test here instead of trying dependent import steps.
            XCTAssertTrue(target.waitForExistence(timeout: 15), app.debugDescription)
            target.tap()
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed, app.debugDescription)
            app.activate()
            tap("miniapp.back-to-list")
            tap("incoming.open")
            tap("incoming.apply.incoming-a")
            if index == 0 {
                let failure = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "診断: 保存後の応答失敗"), object: app.staticTexts["incoming.message"])
                XCTAssertEqual(XCTWaiter.wait(for: [failure], timeout: 15), .completed, app.debugDescription)
                tap("incoming.apply.incoming-a")
            }
            XCTAssertTrue(app.staticTexts["未取込みの共有データはありません。"].waitForExistence(timeout: 10), app.debugDescription)
            tap("閉じる")
            try open("incoming-a")
            expect(app.staticTexts["p1.incoming.status"], "loaded")
            XCTAssertEqual(app.staticTexts["p1.incoming.count"].label, String(beforeA + index + 1))
            let expected = type == "text" ? "Shared text from incoming-a" : type == "url" ? "https://example.com/incoming-a" : "Shared file from incoming-a"
            XCTAssertTrue(app.staticTexts["p1.incoming.contents"].label.contains(expected))
        }
        app.terminate()
        app.launch()
        try open("incoming-b")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        XCTAssertEqual(app.staticTexts["p1.incoming.count"].label, beforeB)
        try open("incoming-a")
        expect(app.staticTexts["p1.incoming.status"], "loaded")
        XCTAssertEqual(app.staticTexts["p1.incoming.count"].label, String(beforeA + 3))
    }

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
        tap("incoming.discard.incoming-a")
        XCTAssertTrue(app.alerts.buttons["破棄する"].waitForExistence(timeout: 10), app.debugDescription)
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["incoming.apply.incoming-a"].exists)
        XCTAssertTrue(app.buttons["incoming.apply.incoming-b"].exists)
        tap("incoming.apply.incoming-a")
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "診断: 保存後の応答失敗"), object: app.staticTexts["incoming.message"])
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 15), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["破棄する"].exists, "Receiving must not also activate the row's discard action")

        // A committed before the injected response failure. Restart retains its
        // pending receipt; the stable ID prevents a second business commit.
        app.terminate()
        app.launch()
        tap("incoming.open")
        tap("incoming.apply.incoming-a")
        expect(app.staticTexts["incoming.message"], "取り込みました。")
        XCTAssertFalse(app.buttons["破棄する"].exists, "Retry must not present discard confirmation")
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
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription)
        button.tap()
    }
    private func expect(_ element: XCUIElement, _ text: String) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 15), .completed, app.debugDescription)
    }
}
