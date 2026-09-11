import XCTest

/// Copied only into the temporary generated host used by CI.
@MainActor
final class PackageResourceHostUITests: XCTestCase {
    func testHostLanguageSelectsEachPackagesOrdinaryLocalization() throws {
        let cases = [
            (language: "en", locale: "en_US", result: "A|Hello from A|B|Hello from B"),
            (language: "ja", locale: "ja_JP", result: "A|Aからこんにちは|B|Bからこんにちは"),
            // The host has no fr InfoPlist.strings. Its packages intentionally do.
            (language: "fr", locale: "fr_FR", result: "A|Bonjour de A|B|Bonjour de B"),
        ]
        for item in cases {
            let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
            app.launchArguments = ["-AppleLanguages", "(\(item.language))", "-AppleLocale", item.locale]
            app.launch()
            XCUIDevice.shared.system.open(try XCTUnwrap(
                URL(string: "jibunkit://mini-app/package-resource-host")
            ))
            let language = app.staticTexts.matching(identifier: "package-resource-host.language")
                .matching(NSPredicate(format: "label == %@", item.language)).firstMatch
            XCTAssertTrue(language.waitForExistence(timeout: 10),
                          "requested \(item.language), observed UI:\n\(app.debugDescription)")
            let result = app.staticTexts.matching(identifier: "package-resource-host.result")
                .matching(NSPredicate(format: "label == %@", item.result)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
            print("PACKAGE_RESOURCE_HOST_RESULT requested=\(item.language) observed=\(language.label) \(result.label)")
            app.terminate()
        }
    }
}
