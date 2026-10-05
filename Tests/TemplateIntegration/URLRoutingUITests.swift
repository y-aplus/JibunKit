import XCTest

@MainActor
final class URLRoutingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCustomURLRoutesColdAndWarmPreservingOtherOwner() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        func tap(_ id: String) {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 15), app.debugDescription)
            app.buttons[id].tap()
        }
        func location(_ value: String) {
            let text = app.staticTexts.matching(identifier: "url.route.location")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 15), app.debugDescription)
        }
        func open(_ address: String) throws {
            XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: address)))
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        }
        func switchTo(_ owner: String) {
            // The switcher is on the Feature root; leave a detail first.
            if !app.buttons["miniapp.back-to-list"].exists {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            let menu = app.buttons["miniapp.back-to-list"]
            XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription)
            menu.press(forDuration: 1.0)
            tap("miniapp.switch.\(owner)")
        }

        app.terminate()
        try open("jkrouteprobe://url-a/detail")
        location("url-a:detail")
        switchTo("url-b")
        location("url-b:root")
        tap("url.route.manual")
        location("url-b:manual")
        try open("jkrouteprobe://url-a/detail")
        location("url-a:detail")
        switchTo("url-b")
        location("url-b:manual")
        for address in ["jkrouteprobe://unknown/", "jkrouteprobe://ambiguous/",
                        "jkrouteprobe://url-a/invalid-destination", "jkrouteprobe://url-a/detail?delete=true"] {
            try open(address)
            location("url-b:manual")
        }
        try open("jkrouteprobe://url-a/")
        location("url-a:root")
        switchTo("url-b")
        location("url-b:manual")
    }
}
