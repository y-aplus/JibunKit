import XCTest

@MainActor
final class P0BPresentationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFeatureOwnedPresentationsCancelAndExternalRouteKeepsCorrectOwner() throws {
        let app = launch()
        open("presentation-a", in: app)

        tap("presentation.show.sheet", in: app)
        tap("presentation.cancel.sheet", in: app)
        expectStatus("ended sheet", in: app)

        tap("presentation.show.cover", in: app)
        tap("presentation.cancel.cover", in: app)
        expectStatus("ended cover", in: app)

        tap("presentation.show.uikit", in: app)
        tap("presentation.cancel.uikit", in: app)
        expectStatus("ended uikit", in: app)

        tap("presentation.show.sheet", in: app)
        try XCUIDevice.shared.system.open(XCTUnwrap(URL(string: "jibunkit://mini-app/presentation-b")))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        expectOwner("presentation-b", in: app)
        switchTo("presentation-a", in: app)
        expectStatus("ended sheet", in: app)
    }

    func testStoppingAAndStartingNewGenerationKeepsBUsable() {
        let app = launch()
        open("presentation-b", in: app)
        tap("presentation.show.sheet", in: app)
        tap("presentation.cancel.sheet", in: app)
        expectStatus("ended sheet", in: app)

        switchTo("presentation-a", in: app)
        tap("presentation.show.uikit", in: app)
        tap("presentation.stop.uikit", in: app)
        let resume = app.buttons["miniapp.start.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), app.debugDescription)
        resume.tap()
        XCTAssertTrue(app.buttons["presentation.show.uikit"].waitForExistence(timeout: 15), app.debugDescription)
        expectStatus("owner stopped", in: app)

        switchTo("presentation-b", in: app)
        expectStatus("ended sheet", in: app)
        tap("presentation.show.uikit", in: app)
        tap("presentation.cancel.uikit", in: app)
        expectStatus("ended uikit", in: app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func open(_ owner: String, in app: XCUIApplication) {
        tap("miniapp.\(owner)", in: app)
        expectOwner(owner, in: app)
    }

    private func switchTo(_ owner: String, in app: XCUIApplication) {
        tap("miniapp.switch.open", in: app)
        tap("miniapp.switch.\(owner)", in: app)
        expectOwner(owner, in: app)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
        element.tap()
    }

    private func expectOwner(_ owner: String, in app: XCUIApplication) {
        let label = app.staticTexts["presentation.owner"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", owner), object: label
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }

    private func expectStatus(_ status: String, in app: XCUIApplication) {
        let label = app.staticTexts["presentation.status"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", status), object: label
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }
}
