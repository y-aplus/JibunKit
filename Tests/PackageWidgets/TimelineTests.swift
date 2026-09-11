import WidgetFeatureA
import WidgetFeatureB
import WidgetKit
import XCTest

final class TimelineTests: XCTestCase {
    func testPackageTimelinesRemainOwnerScoped() {
        let a = FeatureAProvider.fixtureTimeline()
        let b = FeatureBProvider.fixtureTimeline()
        XCTAssertEqual(FeatureAWidget.kind, "com.jibunkit.fixture.feature-a.widget")
        XCTAssertEqual(FeatureBWidget.kind, "com.jibunkit.fixture.feature-b.widget")
        XCTAssertNotEqual(FeatureAWidget.kind, FeatureBWidget.kind)
        XCTAssertEqual(a.entries.map(\.owner), ["owner-a"])
        XCTAssertEqual(b.entries.map(\.owner), ["owner-b"])
        XCTAssertEqual(a.entries.map(\.storageKey), ["owner-a.shared-value"])
        XCTAssertEqual(b.entries.map(\.storageKey), ["owner-b.shared-value"])
    }
}
