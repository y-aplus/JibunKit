import FeatureA
import XCTest

@MainActor
final class StandaloneATests: XCTestCase {
    func testUsesVendorA() {
        XCTAssertEqual(FeatureAClient.sdkVersion, "vendor-a-1.0")
        XCTAssertEqual(FeatureAClient.configuration, "vendor-a-default")
        FeatureAClient.configuration = "standalone-a"
        XCTAssertEqual(FeatureAClient.configuration, "standalone-a")
    }
}
