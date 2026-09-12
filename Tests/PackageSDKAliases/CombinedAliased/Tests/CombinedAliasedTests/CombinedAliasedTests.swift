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

        FeatureAClient.configuration = "combined-a-updated"

        XCTAssertEqual(FeatureAClient.configuration, "combined-a-updated")
        XCTAssertEqual(FeatureBClient.configuration, "vendor-b-default")
    }
}
