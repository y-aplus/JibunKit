import XCTest

/// Normal Registry/UI wiring; OS Shortcuts discovery and workflow execution
/// remain separate device criteria for the 0.8 candidate.
@MainActor
final class P1IntentsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    func testNormalHostKeepsDisabledAAndWritableBAcrossRelaunch() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        tap("management.open")
        for owner in ["a", "b"] {
            P1UIVisibility.reveal(app.staticTexts["management.status.intent-fixture-" + owner], in: app)
            let enable = app.buttons["management.enable.intent-fixture-" + owner]
            if enable.exists {
                enable.tap()
                expectManagement(owner, "有効")
            }
        }
        tap("閉じる")
        try open("intent-fixture-b")
        let value = app.staticTexts["p1.intent.value"]
        let old = try XCTUnwrap(Int(value.label.dropFirst(2)))
        tap("p1.intent.add")
        expect(value, "B:\(old + 1)")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.disable.intent-fixture-a")
        expectManagement("a", "無効（データを保持）")
        app.terminate()
        app.launch()
        tap("management.open")
        expectManagement("a", "無効（データを保持）")
        tap("閉じる")
        try open("intent-fixture-b")
        expect(value, "B:\(old + 1)")
        tap("p1.intent.add")
        expect(value, "B:\(old + 2)")
        tap("miniapp.back-to-list")
        tap("management.open")
        tap("management.enable.intent-fixture-a")
        expectManagement("a", "有効")
    }

    private func open(_ id: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + id)))
        XCTAssertTrue(app.staticTexts["p1.intent.value"].waitForExistence(timeout: 15), app.debugDescription)
        // The view first appears with zero; wait for its asynchronous store read.
        tap("値と候補を再読込")
        expect(app.staticTexts["p1.intent.status"], "completed")
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        P1UIVisibility.reveal(button, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }
    private func expectManagement(_ owner: String, _ text: String) {
        let status = app.staticTexts["management.status.intent-fixture-" + owner]
        P1UIVisibility.reveal(status, in: app)
        // Same native cleanup allowance as the complete host's Web checks.
        expect(status, text, timeout: 120)
    }
    private func expect(_ element: XCUIElement, _ text: String, timeout: TimeInterval = 15) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
}
