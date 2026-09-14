import XCTest
import Vision

@MainActor
final class GalleryUITests: WidgetGalleryTestCase {
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
            let appHeader = springboard.otherElements[appName].firstMatch
            let preview = springboard.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS %@ AND label CONTAINS %@",
                    appName, titleText
                )
            ).firstMatch
            let expectedValue = widget == "A" ? "A:11" : "B:22"
            guard require(title, timeout: 10, on: springboard) else { return }
            guard require(appHeader, timeout: 10, on: springboard) else { return }
            guard require(preview, timeout: 10, on: springboard) else { return }
            guard isVisible(title, in: springboard), isVisible(appHeader, in: springboard),
                  isVisible(preview, in: springboard) else {
                recordFailure(on: springboard, message: "Expected Widget preview is not visible: \(widget)")
                return
            }
            let previewScreenshot = springboard.screenshot()
            guard assertText(
                expected: [expectedValue],
                in: previewScreenshot,
                region: preview.frame,
                screenFrame: springboard.frame,
                evidenceName: "\(appName)-\(widget)-preview"
            ) else { return }
            let add = addWidgetControl(in: springboard)
            guard require(add, timeout: 5, on: springboard) else { return }
            guard isVisible(add, in: springboard) else {
                recordFailure(on: springboard, message: "Observed Add Widget Button is outside the preview")
                return
            }
            print("ADD WIDGET CONTROL: \(add.debugDescription)")
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            guard waitUntilAbsent(title, timeout: 10, on: springboard) else { return }
        }

        let initialValues = expected.map { $0 == "A" ? "A:11" : "B:22" }
        guard waitForText(
            expected: initialValues,
            absent: [],
            timeout: 15,
            on: springboard,
            evidenceName: "\(appName)-widget-render"
        ) else { return }

        if expected.contains("A") && expected.contains("B") {
            app.activate()
            app.buttons["widget-fixture.update-a"].tap()
            guard require(app.staticTexts["a-updated"], timeout: 5, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:33", "B:22"],
                absent: ["A:11"],
                timeout: 20,
                on: springboard,
                evidenceName: "\(appName)-widget-updated"
            ) else { return }

            app.terminate()
            app.launch()
            guard require(app.staticTexts["ready"], timeout: 10, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:33", "B:22"], absent: ["A:11"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-updated-cold-launch"
            ) else { return }

            app.activate()
            app.buttons["widget-fixture.disable-a"].tap()
            guard require(app.staticTexts["a-disabled"], timeout: 5, on: app) else { return }
            app.terminate()
            app.launch()
            guard require(app.staticTexts["ready"], timeout: 10, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:--", "B:22"], absent: ["A:33"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-a-disabled"
            ) else { return }

            app.activate()
            app.buttons["widget-fixture.enable-a"].tap()
            guard require(app.staticTexts["a-enabled"], timeout: 5, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:33", "B:22"], absent: ["A:--"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-a-enabled"
            ) else { return }

            app.activate()
            app.buttons["widget-fixture.delete-a"].tap()
            guard require(app.staticTexts["a-deleted"], timeout: 5, on: app) else { return }
            app.terminate()
            app.launch()
            guard require(app.staticTexts["ready"], timeout: 10, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:--", "B:22"], absent: ["A:33"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-a-deleted"
            ) else { return }

            app.activate()
            app.buttons["widget-fixture.reregister-a"].tap()
            guard require(app.staticTexts["a-reregistered"], timeout: 5, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:empty", "B:22"], absent: ["A:--", "A:33", "A:11"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-a-reregistered-empty"
            ) else { return }

            app.activate()
            app.buttons["widget-fixture.recreate-a"].tap()
            guard require(app.staticTexts["a-recreated"], timeout: 5, on: app) else { return }
            springboard.activate()
            guard waitForText(
                expected: ["A:44", "B:22"], absent: ["A:empty", "A:33"], timeout: 20,
                on: springboard, evidenceName: "\(appName)-widget-a-recreated"
            ) else { return }
        }
    }

}
