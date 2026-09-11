import XCTest

@MainActor
final class GalleryUITests: XCTestCase {
    func testWidgetsAreDiscoveredAndRenderedFromSharedStorage() {
        let expected = (Bundle(for: Self.self).object(forInfoDictionaryKey: "ExpectedWidgets") as! String)
            .split(separator: ",").map(String.init)
        let appName = Bundle(for: Self.self).object(forInfoDictionaryKey: "WidgetAppName") as! String
        let app = XCUIApplication()
        app.launch()
        guard require(app.staticTexts["ready"], timeout: 10, on: app) else { return }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        for widget in expected {
            guard openGallery(on: springboard) else { return }
            guard select(appName: appName, widgetName: "Feature \(widget)", on: springboard) else { return }
            let add = springboard.buttons.matching(
                NSPredicate(format: "label IN %@", ["Add Widget", "ウィジェットを追加"])
            ).firstMatch
            guard require(add, timeout: 10, on: springboard) else { return }
            add.tap()
        }

        if expected.contains("A") {
            guard require(springboard.staticTexts["A:11"], timeout: 15, on: springboard) else { return }
        }
        if expected.contains("B") {
            guard require(springboard.staticTexts["B:22"], timeout: 15, on: springboard) else { return }
        }

        if expected.contains("A") && expected.contains("B") {
            app.activate()
            app.buttons["widget-fixture.update-a"].tap()
            guard require(app.staticTexts["a-updated"], timeout: 5, on: app) else { return }
            springboard.activate()
            guard require(springboard.staticTexts["A:33"], timeout: 20, on: springboard) else { return }
            guard require(springboard.staticTexts["B:22"], timeout: 1, on: springboard) else { return }
        }

        let evidence = XCTAttachment(screenshot: springboard.screenshot())
        evidence.name = "\(appName)-widget-render"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func openGallery(on springboard: XCUIApplication) -> Bool {
        var add = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Add", "追加", "Add Widget", "ウィジェットを追加"])
        ).firstMatch
        if !add.waitForExistence(timeout: 2) {
            let edit = springboard.buttons.matching(
                NSPredicate(format: "label IN %@", ["Edit", "編集"])
            ).firstMatch
            if !edit.exists {
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 2)
            }
            guard require(edit, timeout: 5, on: springboard) else { return false }
            edit.tap()
            add = springboard.buttons.matching(
                NSPredicate(format: "label IN %@", ["Add", "追加", "Add Widget", "ウィジェットを追加"])
            ).firstMatch
        }
        guard require(add, timeout: 10, on: springboard) else { return false }
        add.tap()
        return true
    }

    private func select(appName: String, widgetName: String, on springboard: XCUIApplication) -> Bool {
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(appName)
        }
        let result = springboard.staticTexts[appName].firstMatch
        guard require(result, timeout: 10, on: springboard) else { return false }
        // The iOS 26 gallery exposes this label with a valid on-screen frame but
        // reports the child StaticText as non-hittable. Tap its proven frame;
        // do not guess at an unobserved parent cell type.
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let add = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Add Widget", "ウィジェットを追加"])
        ).firstMatch
        let widget = springboard.staticTexts[widgetName].firstMatch
        if widgetName == "Feature A", add.waitForExistence(timeout: 5) { return true }
        for _ in 0..<3 where !isVisible(widget, in: springboard) {
            springboard.swipeLeft()
        }
        guard require(widget, timeout: 10, on: springboard) else { return false }
        guard isVisible(widget, in: springboard) else {
            recordFailure(on: springboard, message: "Widget configuration is not visible: \(widgetName)")
            return false
        }
        return true
    }

    private func isVisible(_ element: XCUIElement, in application: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && application.frame.intersects(frame)
    }

    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval,
        on application: XCUIApplication
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            recordFailure(on: application, message: "Required element is absent: \(element)")
            return false
        }
        return true
    }

    private func recordFailure(on application: XCUIApplication, message: String) {
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: application.debugDescription)
        hierarchy.name = "accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(message)
    }
}
