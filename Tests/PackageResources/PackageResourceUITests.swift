import XCTest

@MainActor
final class PackageResourceUITests: XCTestCase {
    func testConfiguredPackageReadsOwnResources() {
        for (language, locale) in [("en", "en_US"), ("ja", "ja_JP")] {
            let app = XCUIApplication(bundleIdentifier: "com.jibunkit.package-resource-probe")
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            let result = app.staticTexts["package-resource.result"]
            XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(result.label.hasPrefix("passed:"), result.label)
            print("PACKAGE_RESOURCE_RESULT language=\(language) \(result.label)")
            app.terminate()
        }
    }
}
