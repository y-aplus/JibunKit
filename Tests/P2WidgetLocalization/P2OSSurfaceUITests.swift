import XCTest

/// Simulator-only OS-surface checks. A physical-device run remains necessary
/// for hardware camera behavior; these tests prove rendered OS copy and actual
/// iPadOS window-session restoration without claiming physical-device coverage.
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
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-ar")))
        let permissionCopy = app.buttons["p2.ar.camera-permission-copy"]
        XCTAssertTrue(permissionCopy.waitForExistence(timeout: 15), app.debugDescription)
        permissionCopy.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let purpose = springboard.staticTexts["Use the camera for the foreground AR feature."]
        XCTAssertTrue(purpose.waitForExistence(timeout: 10), springboard.debugDescription)
        let deny = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 5), springboard.debugDescription)
        deny.tap()
    }

    func testTwoWindowsRestoreDistinctOwnersAndStateThenCloseOne() throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-scene-a")))
        var windows = waitForWindows(count: 1)
        var aWindow = try window(owner: "p2-scene-a", in: windows)
        let initialA = try XCTUnwrap(Int(value("p2.scene.count", in: aWindow)))
        tap(aWindow.buttons["p2.scene.increment"], in: aWindow)
        let retainedA = String(initialA + 1)
        let aSession = value("p2.scene.session", in: aWindow)
        tap(aWindow.buttons["p2.scene.new-window"], in: aWindow)

        windows = waitForWindows(count: 2)
        let newWindow = try XCTUnwrap(windows.first { !$0.staticTexts["p2.scene.owner"].exists })
        let search = newWindow.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), newWindow.debugDescription)
        search.tap()
        search.typeText("Scene B")
        tap(newWindow.buttons["miniapp.p2-scene-b"], in: newWindow)
        var bWindow = try window(owner: "p2-scene-b", in: waitForWindows(count: 2))
        let initialB = try XCTUnwrap(Int(value("p2.scene.count", in: bWindow)))
        tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
        tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
        var retainedB = String(initialB + 2)
        if retainedB == retainedA {
            tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
            retainedB = String(initialB + 3)
        }
        let bSession = value("p2.scene.session", in: bWindow)
        XCTAssertNotEqual(aSession, bSession)
        XCTAssertNotEqual(retainedA, retainedB, "The two restored windows need distinguishable state")

        // Give SwiftUI the normal background lifecycle before process death;
        // killing an active app does not establish a scene save opportunity.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launch()
        windows = waitForWindows(count: 2)
        aWindow = try window(owner: "p2-scene-a", in: windows)
        bWindow = try window(owner: "p2-scene-b", in: windows)
        XCTAssertEqual(value("p2.scene.session", in: aWindow), aSession)
        XCTAssertEqual(value("p2.scene.session", in: bWindow), bSession)
        XCTAssertEqual(value("p2.scene.count", in: aWindow), retainedA)
        XCTAssertEqual(value("p2.scene.count", in: bWindow), retainedB)

        tap(aWindow.buttons["p2.scene.close-window"], in: aWindow)
        windows = waitForWindows(count: 1)
        bWindow = try window(owner: "p2-scene-b", in: windows)
        XCTAssertEqual(value("p2.scene.session", in: bWindow), bSession)
        XCTAssertEqual(value("p2.scene.count", in: bWindow), retainedB)
    }

    private func waitForWindows(count: Int) -> [XCUIElement] {
        let deadline = Date().addingTimeInterval(20)
        while app.windows.count != count && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(app.windows.count, count, app.debugDescription)
        return app.windows.allElementsBoundByIndex
    }

    private func window(owner: String, in windows: [XCUIElement]) throws -> XCUIElement {
        try XCTUnwrap(windows.first { window in
            let value = window.staticTexts["p2.scene.owner"]
            return value.exists && value.label == owner
        }, "No OS window displays owner \(owner): \(app.debugDescription)")
    }

    private func tap(_ element: XCUIElement, in window: XCUIElement) {
        let deadline = Date().addingTimeInterval(10)
        while (!element.exists || !element.isHittable) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(element.exists && element.isHittable, window.debugDescription)
        element.tap()
    }

    private func value(_ identifier: String, in window: XCUIElement) -> String {
        let element = window.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), window.debugDescription)
        return element.label
    }
}
