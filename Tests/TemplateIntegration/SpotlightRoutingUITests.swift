import XCTest

@MainActor
final class SpotlightRoutingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testNativeSearchOpensOwnerDetailPreservesOtherPathAndColdLaunches() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
            button.tap()
        }
        func switchTo(_ owner: String) {
            tap("miniapp.switch.open")
            tap("miniapp.switch.\(owner)")
        }
        func status(_ value: String) {
            let text = app.staticTexts.matching(identifier: "spotlight.route.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 30), app.debugDescription)
        }
        func destination(_ value: String) {
            let text = app.staticTexts.matching(identifier: "spotlight.route.destination")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 20), app.debugDescription)
        }
        func openSearchResult(_ title: String) {
            XCUIDevice.shared.press(.home)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            springboard.swipeDown()
            let search = springboard.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 15), springboard.debugDescription)
            search.tap()
            if let old = search.value as? String, !old.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            search.typeText(title)
            let result = springboard.staticTexts[title].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30), springboard.debugDescription)
            result.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), springboard.debugDescription)
        }

        tap("miniapp.spotlight-link-b")
        tap("spotlight.route.index")
        status("ready")
        let bTitle = app.staticTexts["spotlight.route.title"].label
        tap("spotlight.route.manual")
        destination("spotlight-link-b:manual")
        switchTo("spotlight-link-a")
        tap("spotlight.route.index")
        status("ready")
        let aTitle = app.staticTexts["spotlight.route.title"].label
        switchTo("spotlight-link-b")
        destination("spotlight-link-b:manual")
        openSearchResult(aTitle)
        destination("spotlight-link-a:detail")
        switchTo("spotlight-link-b")
        destination("spotlight-link-b:manual")
        app.terminate()
        openSearchResult(bTitle)
        destination("spotlight-link-b:detail")
        tap("spotlight.route.clear")
        status("removed")
    }
}
