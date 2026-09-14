import XCTest

/// CI first installs/launches the normal Counter-only Widget host at this same
/// bundle/version, then Xcode installs this diagnostic host without uninstalling.
@MainActor
final class P1WidgetGalleryUITests: WidgetGalleryTestCase {
    func testNormalToDiagnosticUpdateExposesBothWidgetPreviews() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        var values: [String: String] = [:]
        for owner in ["a", "b"] {
            XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/owner-" + owner)))
            let status = app.staticTexts["widget-feature-" + owner + ".status"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'ready'"), object: status)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
            app.buttons["widget-feature-" + owner + ".increment"].tap()
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'updated'"), object: status)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed, app.debugDescription)
            values[owner] = app.staticTexts["widget-feature-" + owner + ".value"].label
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        for owner in ["a", "b"] {
            guard openGallery(on: springboard) else { return }
            let name = "Feature " + owner.uppercased()
            guard select(appName: "JibunKit", widgetName: name, on: springboard) else { return }
            let preview = springboard.buttons.matching(NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@", "JibunKit", name)).firstMatch
            guard require(preview, timeout: 10, on: springboard), isVisible(preview, in: springboard) else {
                recordFailure(on: springboard, message: "P1 Widget preview is not visible: " + name)
                return
            }
            let expected = owner.uppercased() + ":" + (try XCTUnwrap(values[owner]))
            guard assertText(expected: [expected], in: springboard.screenshot(), region: preview.frame,
                             screenFrame: springboard.frame, evidenceName: "p1-updated-gallery-" + owner) else { return }
            let add = addWidgetControl(in: springboard)
            guard require(add, timeout: 5, on: springboard), isVisible(add, in: springboard) else { return }
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            guard waitUntilAbsent(springboard.staticTexts[name].firstMatch, timeout: 10, on: springboard) else { return }
        }
        _ = waitForText(expected: ["A:" + (try XCTUnwrap(values["a"])), "B:" + (try XCTUnwrap(values["b"]))],
                        absent: [], timeout: 20, on: springboard, evidenceName: "p1-updated-home-widgets")
    }
}
