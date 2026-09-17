#if os(iOS)
import XCTest
import JibunKitCore

@MainActor
final class P2LocationNativeTests: XCTestCase {
    func testProbePublishesTwoRealFeatureDefinitionsWithSeparateOwners() {
        let definitions = P2LocationProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-location-tracker"), MiniAppID("p2-location-regions")])
        XCTAssertEqual(definitions.flatMap(\.permissions).map(\.id), ["location", "location"])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onHostLaunch != nil && $0.onUnregister != nil })
    }

    func testRealFeatureLifetimesStartAndStopIndependently() async throws {
        let tracker = P2LocationProbe.tracker.definition
        let regions = P2LocationProbe.regions.definition
        try await tracker.lifetime?.start(); try await regions.lifetime?.start()
        let regionRuntime = regions.lifetime?.runtime
        await tracker.lifetime?.stop()
        XCTAssertTrue(regions.lifetime?.runtime === regionRuntime)
        XCTAssertEqual(regions.lifetime?.state, .running)
        await regions.lifetime?.stop()
    }

    func testHostLaunchHookIsSynchronousAndIdempotent() throws {
        let definitions = P2LocationProbe.definitions
        for definition in definitions { try definition.onHostLaunch?(); try definition.onHostLaunch?() }
    }
}
#endif
