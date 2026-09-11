import XCTest
import Vision

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
        }
    }

    private func waitForText(
        expected: [String],
        absent: [String],
        timeout: TimeInterval,
        on application: XCUIApplication,
        evidenceName: String
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var screenshot: XCUIScreenshot
        var recognized: [String]
        repeat {
            screenshot = application.screenshot()
            recognized = recognizeText(in: screenshot, region: application.frame, screenFrame: application.frame)
            let values = normalizedValues(recognized)
            if expected.allSatisfy({ values.contains(normalize($0)) }) &&
                absent.allSatisfy({ !values.contains(normalize($0)) }) {
                attachOCR(screenshot: screenshot, recognized: recognized, name: evidenceName)
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        } while Date() < deadline

        attachOCR(screenshot: screenshot, recognized: recognized, name: evidenceName)
        XCTFail("OCR mismatch for \(evidenceName); expected=\(expected), absent=\(absent), recognized=\(recognized)")
        return false
    }

    private func assertText(
        expected: [String],
        in screenshot: XCUIScreenshot,
        region: CGRect,
        screenFrame: CGRect,
        evidenceName: String
    ) -> Bool {
        let recognized = recognizeText(in: screenshot, region: region, screenFrame: screenFrame)
        let values = normalizedValues(recognized)
        attachOCR(screenshot: screenshot, recognized: recognized, name: evidenceName)
        guard expected.allSatisfy({ values.contains(normalize($0)) }) else {
            XCTFail("OCR mismatch for \(evidenceName); expected=\(expected), recognized=\(recognized)")
            return false
        }
        return true
    }

    private func recognizeText(
        in screenshot: XCUIScreenshot,
        region: CGRect,
        screenFrame: CGRect
    ) -> [String] {
        guard let image = screenshot.image.cgImage else {
            return ["<screenshot has no CGImage>"]
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = CGRect(
            x: (region.minX - screenFrame.minX) / screenFrame.width,
            y: 1 - ((region.maxY - screenFrame.minY) / screenFrame.height),
            width: region.width / screenFrame.width,
            height: region.height / screenFrame.height
        )
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        } catch {
            return ["<Vision error: \(error)>"]
        }
    }

    private func normalize(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private func normalizedValues(_ recognized: [String]) -> Set<String> {
        Set(recognized.map { normalize($0) })
    }

    private func attachOCR(screenshot: XCUIScreenshot, recognized: [String], name: String) {
        let image = XCTAttachment(screenshot: screenshot)
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let text = XCTAttachment(string: recognized.joined(separator: "\n"))
        text.name = "\(name)-recognized-text"
        text.lifetime = .keepAlways
        add(text)
        print("OCR \(name): \(recognized)")
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
        springboard.buttons.matching(
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
