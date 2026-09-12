import FeatureA
import FeatureB
import XCTest

@MainActor
final class CombinedAliasedTests: XCTestCase {
    func testBothSDKConfigurationsRemainIndependent() {
        XCTAssertEqual(FeatureAClient.sdkVersion, "vendor-a-1.0")
        XCTAssertEqual(FeatureBClient.sdkVersion, "vendor-b-2.0")
        XCTAssertEqual(FeatureAClient.configuration, "vendor-a-default")
        XCTAssertEqual(FeatureBClient.configuration, "vendor-b-default")

        FeatureBClient.configuration = "combined-b-written"
        XCTAssertEqual(FeatureAClient.configuration, "vendor-a-default")
        XCTAssertEqual(FeatureBClient.configuration, "combined-b-written")

        FeatureAClient.configuration = "combined-a-updated"

        XCTAssertEqual(FeatureAClient.configuration, "combined-a-updated")
        XCTAssertEqual(FeatureBClient.configuration, "combined-b-written")
    }
}
