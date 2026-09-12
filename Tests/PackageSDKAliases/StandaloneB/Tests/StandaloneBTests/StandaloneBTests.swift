import FeatureB
import XCTest

@MainActor
final class StandaloneBTests: XCTestCase {
    func testUsesVendorB() {
        XCTAssertEqual(FeatureBClient.sdkVersion, "vendor-b-2.0")
        XCTAssertEqual(FeatureBClient.configuration, "vendor-b-default")
        FeatureBClient.configuration = "standalone-b"
        XCTAssertEqual(FeatureBClient.configuration, "standalone-b")
    }
}
