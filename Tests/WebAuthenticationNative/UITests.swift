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

    func testOwnerCallbacksReturnOnlyToTheCorrectOwner() {
        complete(startButton: "wrapper.owner-a.complete", status: "completed p1-web-a")
        complete(startButton: "wrapper.owner-b.complete", status: "completed p1-web-b")
    }

    private func complete(startButton: String, status: String = "completed") {
        app.buttons[startButton].tap()
        acceptConsentIfPresent()
        let returnLink = app.links["Return to App"]
        guard waitForReturnPage(returnLink) else { return }
        returnLink.tap()
        confirmOpenIfPresent()
        waitForStatus(status, timeout: 15)
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

    private func waitForReturnPage(_ link: XCUIElement) -> Bool {
        // A cold AuthenticationServices browser can finish presenting its
        // consent/welcome control after the initial short consent check. Wait
        // for real page content and handle that control when it appears.
        let deadline = Date().addingTimeInterval(45)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        while Date() < deadline {
            if link.waitForExistence(timeout: 5) { return true }
            for button in [app.buttons["Continue"], springboard.buttons["Continue"]] {
                if button.exists && button.isHittable { button.tap() }
            }
            let status = app.staticTexts["auth.status"]
            if status.exists && (status.label.hasPrefix("failed") || status.label == "rejected") { break }
        }
        for (name, surface) in [("app", app), ("system", springboard)] {
            let screenshot = XCTAttachment(screenshot: surface.screenshot())
            screenshot.name = "auth-page-missing-" + name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let tree = XCTAttachment(string: surface.debugDescription)
            tree.name = "auth-page-missing-" + name + "-hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTFail("Native authentication page did not become ready; see page-missing attachments")
        return false
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
