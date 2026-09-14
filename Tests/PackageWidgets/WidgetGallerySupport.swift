import XCTest
import Vision

@MainActor
class WidgetGalleryTestCase: XCTestCase {
    func waitForText(
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

    func assertText(
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

    func recognizeText(
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

    func normalize(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    func normalizedValues(_ recognized: [String]) -> Set<String> {
        Set(recognized.map { normalize($0) })
    }

    func attachOCR(screenshot: XCUIScreenshot, recognized: [String], name: String) {
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

    func openGallery(on springboard: XCUIApplication) -> Bool {
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

    func select(appName: String, widgetName: String, on springboard: XCUIApplication) -> Bool {
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
        for _ in 0..<12 where !isVisible(widget, in: springboard) {
            springboard.swipeLeft()
        }
        guard require(widget, timeout: 10, on: springboard) else { return false }
        guard isVisible(widget, in: springboard) else {
            recordFailure(on: springboard, message: "Widget configuration is not visible: \(widgetName)")
            return false
        }
        return true
    }

    func waitUntilAbsent(
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

    func addWidgetControl(in springboard: XCUIApplication) -> XCUIElement {
        springboard.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "Add Widget", "ウィジェットを追加"
            )
        ).firstMatch
    }

    func isVisible(_ element: XCUIElement, in application: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && application.frame.intersects(frame)
    }

    func require(
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

    func recordFailure(on application: XCUIApplication, message: String) {
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
