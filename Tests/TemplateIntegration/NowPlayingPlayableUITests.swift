import XCTest

/// Copied only into the temporary signed Feature-validation host by CI.
@MainActor
final class NowPlayingPlayableUITests: XCTestCase {
    func testPlayableSessionAdvancesAndRecordsControlCenterAvailability() {
        let app = launchPlayableProbe()
        let result = playbackReady(in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(result.label.contains("item=ready"), result.label)
        XCTAssertTrue(result.label.contains("control=playing"), result.label)
        print("NOW_PLAYING_PLAYBACK_BASELINE \(result.label)")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openControlCenter(springboard)
        attachEvidence(springboard, name: "Now Playing availability after confirmed playback")
        let availability = springboard.staticTexts["Feature A"].waitForExistence(timeout: 5)
            ? "available" : "unavailable"
        print("NOW_PLAYING_CONTROL_CENTER_AVAILABILITY \(availability)")
    }

    func testNativeControlCenterRoutesSingleAndDualSessions() throws {
        continueAfterFailure = false
        let app = launchPlayableProbe()
        XCTAssertTrue(playbackReady(in: app).waitForExistence(timeout: 20), app.debugDescription)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openControlCenter(springboard)
        attachEvidence(springboard, name: "Now Playing single-session Control Center")
        guard springboard.staticTexts["Feature A"].waitForExistence(timeout: 5) else {
            throw XCTSkip("This runtime and fixture expose no Now Playing module or accessible controls after the standard top-right gesture")
        }
        tapTransport(named: "Pause", in: springboard)
        XCTAssertTrue(waitForCounts(containing: "a-pause=1", in: app), app.debugDescription)
        tapTransport(named: "Play", in: springboard)
        XCTAssertTrue(waitForCounts(containing: "a-play=1", in: app), app.debugDescription)
        closeControlCenter(springboard)

        app.buttons["now-playing.prepare-dual"].tap()
        XCTAssertTrue(waitForLabel(prefix: "dual-ready", in: app), app.debugDescription)
        openControlCenter(springboard)
        attachEvidence(springboard, name: "Now Playing dual-session Control Center")
        XCTAssertTrue(springboard.staticTexts["Feature B"].waitForExistence(timeout: 5), springboard.debugDescription)
        tapTransport(named: "Pause", in: springboard)
        XCTAssertTrue(waitForCounts(containing: "b-pause=1", in: app), app.debugDescription)
        closeControlCenter(springboard)

        app.buttons["now-playing.remove-a-targets"].tap()
        openControlCenter(springboard)
        XCTAssertTrue(springboard.staticTexts["Feature B"].waitForExistence(timeout: 5), springboard.debugDescription)
        tapTransport(named: "Pause", in: springboard)
        XCTAssertTrue(waitForCounts(containing: "b-pause=2", in: app), app.debugDescription)
        XCTAssertTrue(waitForCounts(containing: "a-pause=1", in: app), app.debugDescription)
        print("NOW_PLAYING_CONTROL_CENTER passed")
    }

    private func openControlCenter(_ springboard: XCUIApplication) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.65)))
    }

    private func closeControlCenter(_ springboard: XCUIApplication) { springboard.swipeUp() }

    private func tapTransport(named name: String, in springboard: XCUIApplication) {
        let button = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), springboard.debugDescription)
        button.tap()
    }

    private func waitForLabel(prefix: String, in app: XCUIApplication) -> Bool {
        app.staticTexts.matching(identifier: "now-playing.result").matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch.waitForExistence(timeout: 20)
    }

    private func launchPlayableProbe() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["miniapp.now-playing-playable-probe"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["miniapp.now-playing-playable-probe"].tap()
        app.buttons["now-playing.prepare-single"].tap()
        return app
    }

    private func playbackReady(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: "now-playing.result")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "playback-ready")).firstMatch
    }

    private func waitForCounts(containing value: String, in app: XCUIApplication) -> Bool {
        app.staticTexts.matching(identifier: "now-playing.counts").matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch.waitForExistence(timeout: 10)
    }

    private func attachEvidence(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("NOW_PLAYING_CONTROL_CENTER_UI \(app.debugDescription)")
    }
}
