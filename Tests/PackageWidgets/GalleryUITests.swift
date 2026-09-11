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
            let titleText = "Feature \(widget)"
            let title = springboard.staticTexts[titleText].firstMatch
            guard select(appName: appName, widgetName: titleText, on: springboard) else { return }
            let previewValue = springboard.staticTexts[widget == "A" ? "A:11" : "B:22"]
            guard require(title, timeout: 10, on: springboard) else { return }
            guard require(previewValue, timeout: 10, on: springboard) else { return }
            guard isVisible(title, in: springboard), isVisible(previewValue, in: springboard) else {
                recordFailure(on: springboard, message: "Expected Widget preview is not visible: \(widget)")
                return
            }
            let add = addWidgetControl(in: springboard)
            if add.waitForExistence(timeout: 5) {
                guard isVisible(add, in: springboard) else {
                    recordFailure(on: springboard, message: "Observed Add Widget label is outside the preview")
                    return
                }
                print("ADD WIDGET CONTROL: \(add.debugDescription)")
                add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                let frame = springboard.frame
                guard abs(frame.width - 402) < 1, abs(frame.height - 874) < 1 else {
                    recordFailure(on: springboard, message: "Refusing preview fallback on unexpected frame: \(frame)")
                    return
                }
                print("ADD WIDGET CONTROL: absent after preview identity \(titleText) / \(previewValue.label); using verified fixture coordinate")
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
            }
            guard waitUntilAbsent(title, timeout: 10, on: springboard) else { return }
            guard require(springboard.staticTexts[widget == "A" ? "A:11" : "B:22"],
                          timeout: 15, on: springboard) else { return }
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

        let widget = springboard.staticTexts[widgetName].firstMatch
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

    private func waitUntilAbsent(
        _ element: XCUIElement,
        timeout: TimeInterval,
        on application: XCUIApplication
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            recordFailure(on: application, message: "Widget gallery preview did not close")
            return false
        }
        return true
    }

    private func addWidgetControl(in springboard: XCUIApplication) -> XCUIElement {
        springboard.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "Add Widget", "ウィジェットを追加"
            )
        ).firstMatch
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
        print("UI FAILURE: \(message)")
        print("ACCESSIBILITY HIERARCHY BEGIN")
        print(application.debugDescription)
        print("ACCESSIBILITY HIERARCHY END")
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
