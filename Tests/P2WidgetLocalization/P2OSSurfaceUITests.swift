import XCTest

/// Simulator-only OS-surface checks. A physical-device run remains necessary
/// for hardware camera behavior; these tests only prove rendered OS copy.
@MainActor
final class P2OSSurfaceUITests: WidgetGalleryTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testNormalCounterWidgetRendersEnglishInGalleryAndHome() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        guard openGallery(on: springboard) else { return }
        guard select(appName: "JibunKit", widgetName: "Counter", on: springboard) else { return }

        XCTAssertTrue(springboard.staticTexts["Shows the value updated by the app and shortcuts."]
            .waitForExistence(timeout: 10), springboard.debugDescription)
        let preview = springboard.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "JibunKit", "Counter")).firstMatch
        guard require(preview, timeout: 10, on: springboard), isVisible(preview, in: springboard) else {
            recordFailure(on: springboard, message: "Normal Counter Widget preview is not visible")
            return
        }
        guard assertText(expected: ["Counter"], in: springboard.screenshot(), region: preview.frame,
                         screenFrame: springboard.frame, evidenceName: "p2-normal-widget-gallery-en") else { return }
        let add = addWidgetControl(in: springboard)
        guard require(add, timeout: 5, on: springboard), isVisible(add, in: springboard) else { return }
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard waitUntilAbsent(add, timeout: 10, on: springboard) else { return }
        _ = waitForText(expected: ["Counter"], absent: [], timeout: 20, on: springboard,
                        evidenceName: "p2-normal-widget-home-en")
    }

    func testCameraPromptRendersRepresentativeEnglishUsageDescription() throws {
        let consent = app.buttons["management.consent.p2-ar.camera"]
        let management = app.buttons["management.open"]
        XCTAssertTrue(management.waitForExistence(timeout: 10), app.debugDescription)
        management.tap()
        for _ in 0..<15 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.waitForExistence(timeout: 10) && consent.isHittable, app.debugDescription)
        consent.tap()
        // The diagnostic management UI is intentionally Japanese; only the
        // app-specific InfoPlist usage text under test is selected as English.
        let allowFeature = app.buttons["許可"]
        XCTAssertTrue(allowFeature.waitForExistence(timeout: 5), app.debugDescription)
        allowFeature.tap()
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()

        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-ar")))
        let start = app.buttons["p2.ar.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
        start.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let purpose = springboard.staticTexts["Use the camera for the foreground AR feature."]
        XCTAssertTrue(purpose.waitForExistence(timeout: 10), springboard.debugDescription)
        let deny = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 5), springboard.debugDescription)
        deny.tap()
    }
}
