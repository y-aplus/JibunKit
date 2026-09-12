import XCTest

@MainActor
final class P0ALifetimeUITests: XCTestCase {
    func testNormalHostSelectionShutdownFailureAndRetryPreserveOtherOwner() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        open("p0-a", in: app)
        expect("a", "g=1,n=0,value=0,ended=0,cleaned=0,state=running", in: app)
        backToList(app)
        open("p0-b", in: app)
        app.buttons["p0.broadcast"].tap()
        app.buttons["p0.send.a"].tap()
        app.buttons["p0.send.b"].tap()
        expect("a", "g=1,n=1,value=11,ended=0,cleaned=0,state=running", in: app)
        expect("b", "g=1,n=1,value=22,ended=0,cleaned=0,state=running", in: app)

        app.buttons["p0.stop.a"].tap()
        expect("a", "g=1,n=1,value=11,ended=1,cleaned=1,state=stopped", in: app)
        app.buttons["p0.broadcast"].tap()
        expect("b", "g=1,n=2,value=22,ended=0,cleaned=0,state=running", in: app)
        expect("a", "g=1,n=1,value=11,ended=1,cleaned=1,state=stopped", in: app)

        app.buttons["p0.fail.a"].tap()
        app.buttons["p0.start.a"].tap()
        expect("a", "g=2,n=1,value=11,ended=2,cleaned=2,state=failed", in: app)
        app.buttons["p0.broadcast"].tap()
        expect("b", "g=1,n=3,value=22,ended=0,cleaned=0,state=running", in: app)
        backToList(app)
        open("p0-a", in: app)
        // Entering a failed owner makes one startup attempt through the normal host.
        expect("a", "g=3,n=1,value=11,ended=2,cleaned=2,state=running", in: app)
        app.buttons["p0.broadcast"].tap()
        expect("a", "g=3,n=2,value=11,ended=2,cleaned=2,state=running", in: app)
        expect("b", "g=1,n=4,value=22,ended=0,cleaned=0,state=running", in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "P0-A-lifetime-two-owner-final"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStartupFailureShowsRetryAndKeepsOtherFeatureRunning() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        open("p0-b", in: app)
        app.buttons["p0.send.b"].tap()
        app.buttons["p0.fail.a"].tap()
        backToList(app)
        open("p0-a", in: app)
        let retry = app.buttons["miniapp.start.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        retry.tap()
        expect("a", "g=2,n=0,value=0,ended=1,cleaned=1,state=running", in: app)
        expect("b", "g=1,n=0,value=22,ended=0,cleaned=0,state=running", in: app)
    }

    private func open(_ id: String, in app: XCUIApplication) {
        let row = app.buttons["miniapp.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
    }
    private func backToList(_ app: XCUIApplication) {
        app.buttons["miniapp.back-to-list"].tap()
    }
    private func expect(_ owner: String, _ text: String, in app: XCUIApplication) {
        let element = app.staticTexts["p0.summary.\(owner)"]
        let result = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 10), .completed, app.debugDescription)
    }
}
