import XCTest

@MainActor
final class SDKAliasHostUITests: XCTestCase {
    func testAliasedSDKConfigurationsRemainIndependentInIOSHost() {
        let app = XCUIApplication()
        app.launch()

        assertText("sdk-alias.a-version", equals: "vendor-a-1.0", in: app)
        assertText("sdk-alias.b-version", equals: "vendor-b-2.0", in: app)
        assertText("sdk-alias.a-configuration", equals: "vendor-a-default", in: app)
        assertText("sdk-alias.b-configuration", equals: "vendor-b-default", in: app)

        guard tapButton("sdk-alias.write-b", in: app) else { return }
        assertText("sdk-alias.a-configuration", equals: "vendor-a-default", in: app)
        assertText("sdk-alias.b-configuration", equals: "ios-b-written", in: app)

        guard tapButton("sdk-alias.update-a", in: app) else { return }
        assertText("sdk-alias.a-configuration", equals: "ios-a-updated", in: app)
        assertText("sdk-alias.b-configuration", equals: "ios-b-written", in: app)
        assertText("sdk-alias.a-version", equals: "vendor-a-1.0", in: app)
        assertText("sdk-alias.b-version", equals: "vendor-b-2.0", in: app)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "sdk-alias-ios-final"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func assertText(_ identifier: String, equals expected: String, in app: XCUIApplication) {
        let text = app.staticTexts[identifier]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", expected),
            object: text
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            "Expected \(identifier) to display exactly \(expected); observed \(text.label)"
        )
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[identifier]
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Missing button: \(identifier)")
            return false
        }
        button.tap()
        return true
    }
}
