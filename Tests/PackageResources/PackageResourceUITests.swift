import XCTest

@MainActor
final class PackageResourceUITests: XCTestCase {
    func testConfiguredPackageReadsOwnResources() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.package-resource-probe")
        app.launch()
        let result = app.staticTexts["package-resource.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(result.label.hasPrefix("passed:"), result.label)
        print("PACKAGE_RESOURCE_RESULT \(result.label)")
    }
}
