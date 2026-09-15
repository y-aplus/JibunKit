import XCTest

/// Independent cases ensure a text failure does not hide URL/file observations.
@MainActor
final class P1IncomingOSDiagnosticUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    func testTextShare() throws { try receive("text") }
    func testURLShare() throws { try receive("url") }
    func testFileShare() throws { try receive("file") }

    private func receive(_ kind: String) throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/incoming-a")))
        let link = app.buttons["p1.incoming.share." + kind]
        XCTAssertTrue(link.waitForExistence(timeout: 15), app.debugDescription)
        link.tap()
        let activity = app.collectionViews["activityCollectionView"].cells.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "shareCell", "JibunKit")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10), app.debugDescription)
        activity.tap()
        let target = app.buttons["share.destination.incoming-a"]
        let error = app.staticTexts["share.error"]
        let prepared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists || error.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 20), .completed, app.debugDescription)
        if error.exists {
            XCTFail("OS_SHARE \(kind) preparation: \(error.label)\n\(app.debugDescription)")
            return
        }
        XCTAssertTrue(target.exists, app.debugDescription)
        target.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !target.exists || error.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 20), .completed, app.debugDescription)
        if error.exists {
            XCTFail("OS_SHARE \(kind) enqueue: \(error.label)\n\(app.debugDescription)")
            return
        }
        app.activate()
        app.buttons["miniapp.back-to-list"].tap()
        let inbox = app.buttons["incoming.open"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10), app.debugDescription)
        inbox.tap()
        XCTAssertTrue(app.buttons["incoming.apply.incoming-a"].waitForExistence(timeout: 10), app.debugDescription)
        print("OS_SHARE \(kind) reached durable inbox through extension")
    }
}
