import XCTest

final class WebAuthenticationNativeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testNativeBaselineCompletesThroughCustomCallback() {
        complete(startButton: "baseline.complete")
    }

    func testJibunKitWrapperCompletesThroughStandardCallbackDescriptor() {
        complete(startButton: "wrapper.complete")
    }

    func testNativeBaselineOSCancelReturnsCanceledLogin() {
        cancel(startButton: "baseline.cancel")
    }

    func testJibunKitWrapperOSCancelReturnsCanceledLogin() {
        cancel(startButton: "wrapper.cancel")
    }

    private func complete(startButton: String) {
        app.buttons[startButton].tap()
        acceptConsentIfPresent()
        let returnLink = app.links["Return to App"]
        XCTAssertTrue(returnLink.waitForExistence(timeout: 10))
        returnLink.tap()
        confirmOpenIfPresent()
        waitForStatus("completed", timeout: 15)
    }

    private func cancel(startButton: String) {
        app.buttons[startButton].tap()
        acceptConsentIfPresent()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let appCancel = app.buttons.matching(identifier: "Close").firstMatch
        let systemCancel = springboard.buttons.matching(identifier: "Close").firstMatch
        if appCancel.waitForExistence(timeout: 3) { appCancel.tap() }
        else if systemCancel.waitForExistence(timeout: 3) { systemCancel.tap() }
        else { XCTFail("AuthenticationServices cancel control was not visible") }
        waitForStatus("cancelled", timeout: 10)
    }

    private func acceptConsentIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let appContinue = app.buttons["Continue"]
        let systemContinue = springboard.buttons["Continue"]
        if appContinue.waitForExistence(timeout: 2) { appContinue.tap() }
        else if systemContinue.waitForExistence(timeout: 2) { systemContinue.tap() }
    }

    private func confirmOpenIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let appOpen = app.buttons["Open"]
        let systemOpen = springboard.buttons["Open"]
        if appOpen.waitForExistence(timeout: 2) { appOpen.tap() }
        else if systemOpen.waitForExistence(timeout: 2) { systemOpen.tap() }
    }

    private func waitForStatus(_ value: String, timeout: TimeInterval) {
        let status = app.staticTexts["auth.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: status)
        waitForExpectations(timeout: timeout)
    }
}
