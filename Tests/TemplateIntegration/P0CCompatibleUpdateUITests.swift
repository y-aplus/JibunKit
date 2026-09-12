import XCTest

@MainActor
final class P0CCompatibleUpdateV1UITests: XCTestCase {
    func testSeedV1ThroughNormalFeatureURL() throws {
        continueAfterFailure = false
        let app = try launch(stage: "v1-seed")
        expect(
            "passed:v1-seed|seeded-v1|eyJjb3VudCI6N30=|A|Hello from A|Bonjour de A|Aからこんにちは|B|Hello from B|Bonjour de B|Bからこんにちは",
            in: app
        )
    }
}

@MainActor
final class P0CCompatibleUpdateV2UITests: XCTestCase {
    func testReadUpdateRelaunchRejectCorruptionAndRepairWithoutReseeding() throws {
        continueAfterFailure = false
        var app = try launch(stage: "v2-update")
        expect(prefix: "passed:v2-update|old-defaults-updated|eyJjb3VudCI6N30=", in: app)
        app.terminate()

        app = try launch(stage: "v2-relaunch")
        expect(prefix: "passed:v2-relaunch|updated-reloaded|eyJjb3VudCI6N30=", in: app)
        app.terminate()

        app = try launch(stage: "v2-corrupt")
        expect(prefix: "passed:v2-corrupt|corrupt-rejected-preserved|eyJjb3VudCI6N30=", in: app)
        app.terminate()

        app = try launch(stage: "v2-repair")
        expect(prefix: "passed:v2-repair|repaired-reloaded|eyJjb3VudCI6N30=", in: app)
    }
}

@MainActor
private func launch(stage: String) throws -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                           "-P0CCompatibleStage", stage]
    app.launch()
    XCUIDevice.shared.system.open(try XCTUnwrap(
        URL(string: "jibunkit://mini-app/p0-c-compatible-update")
    ))
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    return app
}

@MainActor
private func expect(_ expected: String, in app: XCUIApplication) {
    let result = app.staticTexts["p0c.compatible-update.result"]
    let predicate = NSPredicate(format: "label == %@", expected)
    XCTAssertEqual(
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: result)], timeout: 20),
        .completed,
        app.debugDescription
    )
}

@MainActor
private func expect(prefix: String, in app: XCUIApplication) {
    let result = app.staticTexts["p0c.compatible-update.result"]
    let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
    XCTAssertEqual(
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: result)], timeout: 20),
        .completed,
        app.debugDescription
    )
    XCTAssertTrue(result.label.hasSuffix(
        "|A|Hello from A|Bonjour de A|Aからこんにちは|B|Hello from B|Bonjour de B|Bからこんにちは"
    ), app.debugDescription)
}
