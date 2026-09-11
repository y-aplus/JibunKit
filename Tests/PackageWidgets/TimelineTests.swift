import Foundation
import WidgetFeatureA
import WidgetFeatureB
import WidgetKit
import XCTest

final class TimelineTests: XCTestCase {
    func testPackageTimelinesRemainOwnerScoped() {
        let suite = "com.jibunkit.fixture.widget-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let aStore = FeatureAStore(defaults: defaults)
        let bStore = FeatureBStore(defaults: defaults)
        aStore.set(11)
        bStore.set(22)
        let aProvider = FeatureAProvider(store: aStore)
        let bProvider = FeatureBProvider(store: bStore)
        let a = aProvider.timeline()
        let b = bProvider.timeline()
        XCTAssertEqual(FeatureAWidget.kind, "com.jibunkit.fixture.feature-a.widget")
        XCTAssertEqual(FeatureBWidget.kind, "com.jibunkit.fixture.feature-b.widget")
        XCTAssertNotEqual(FeatureAWidget.kind, FeatureBWidget.kind)
        XCTAssertEqual(a.entries.map(\.owner), ["owner-a"])
        XCTAssertEqual(b.entries.map(\.owner), ["owner-b"])
        XCTAssertEqual(a.entries.map(\.storageKey), ["owner-a.shared-value"])
        XCTAssertEqual(b.entries.map(\.storageKey), ["owner-b.shared-value"])
        XCTAssertEqual(a.entries.map(\.value), [11])
        XCTAssertEqual(b.entries.map(\.value), [22])
        XCTAssertEqual(FeatureAStore.localKey, FeatureBStore.localKey)

        aStore.set(33)
        XCTAssertEqual(aProvider.timeline().entries.map(\.value), [33])
        XCTAssertEqual(bProvider.timeline().entries.map(\.value), [22])
    }
}
