import ContinuingFeatureA
import ContinuingFeatureB
import JibunKitCore
import XCTest

final class ContinuingLiveActivityNativeTests: XCTestCase {
    func testFeatureTypesKeepSameLocalIDSeparatedByOwner() throws {
        XCTAssertEqual(FeatureALiveActivityService.localID, FeatureBLiveActivityService.localID)
        XCTAssertNotEqual(FeatureALiveActivityService.owner, FeatureBLiveActivityService.owner)
        let generation = UUID()
        let a = try MiniAppContinuingIdentity(owner: FeatureALiveActivityService.owner,
            localID: FeatureALiveActivityService.localID, generation: generation)
        let b = try MiniAppContinuingIdentity(owner: FeatureBLiveActivityService.owner,
            localID: FeatureBLiveActivityService.localID, generation: generation)
        XCTAssertNotEqual(a, b)
    }

    func testFeatureContentRetainsDomainMeaning() {
        let a = FeatureAActivityAttributes.ContentState(count: 3, message: "配送中")
        let b = FeatureBActivityAttributes.ContentState(score: 30, phase: "後半")
        XCTAssertEqual(a.message, "配送中")
        XCTAssertEqual(b.phase, "後半")
    }
}
