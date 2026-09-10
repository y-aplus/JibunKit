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
                .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", value, "failed:")).firstMatch
            // The existing native Spotlight probe needed about 40 seconds on CI.
            // Bound the wait consistently, but surface explicit failure immediately.
            XCTAssertTrue(text.waitForExistence(timeout: 90), app.debugDescription)
            XCTAssertEqual(text.label, value, app.debugDescription)
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
            // SpringBoard hosts the gesture, but the searchScreen and keyboard
            // belong to the separate Spotlight process on the CI runtime.
            let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
            let search = spotlight.textFields["SpotlightSearchField"]
            XCTAssertTrue(search.waitForExistence(timeout: 15), spotlight.debugDescription)
            let typingIntroduction = spotlight.otherElements["UIContinuousPathIntroductionView"]
            if typingIntroduction.exists {
                typingIntroduction.buttons["Continue"].tap()
            }
            search.tap()
            if let old = search.value as? String, !old.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            search.typeText(title)
            // Spotlight combines title and description into the result cell's
            // label. Exclude the similarly named web-search suggestion.
            let result = spotlight.cells.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "Identifier:ResultCell,", "\(title), JibunKit native search route probe"
            )).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30), spotlight.debugDescription)
            result.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), spotlight.debugDescription)
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
