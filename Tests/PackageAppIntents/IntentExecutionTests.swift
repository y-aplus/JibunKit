import AppIntents
import IntentFeatureA
import IntentFeatureB
import XCTest

@MainActor
final class IntentExecutionTests: XCTestCase {
    func testPackageIntentExecutionChangesOnlyItsOwner() async throws {
        FeatureAValues.value = 10
        FeatureBValues.value = 100
        defer { FeatureAValues.value = 0; FeatureBValues.value = 0 }
        let a = try await FeatureAAddValueIntent(amount: 3).perform()
        XCTAssertEqual(a.value, 13)
        XCTAssertEqual(FeatureAValues.value, 13)
        XCTAssertEqual(FeatureBValues.value, 100)
        let b = try await FeatureBAddValueIntent(amount: -7).perform()
        XCTAssertEqual(b.value, 93)
        XCTAssertEqual(FeatureAValues.value, 13)
        XCTAssertEqual(FeatureBValues.value, 93)
    }
}
