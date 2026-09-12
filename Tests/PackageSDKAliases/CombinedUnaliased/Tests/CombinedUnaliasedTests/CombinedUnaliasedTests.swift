import FeatureA
import FeatureB
import XCTest

final class CombinedUnaliasedTests: XCTestCase {
    func testGraphRequiresDisambiguation() {
        XCTAssertNotEqual(FeatureAClient.sdkVersion, FeatureBClient.sdkVersion)
    }
}
