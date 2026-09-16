import ContinuingFeatureA
import ContinuingFeatureB
import JibunKitCore
import XCTest

final class ContinuingLiveActivityNativeTests: XCTestCase {
    @MainActor
    func testIntegrationFactoriesProvideManagedContinuingSurfaces() throws {
        let definitions = try [FeatureALiveIntegration.makeDefinition(), FeatureBLiveIntegration.makeDefinition()]
        XCTAssertTrue(definitions.allSatisfy { $0.backup != nil && $0.removal != nil && $0.externalAccess != nil })
        XCTAssertEqual(definitions.map { $0.continuingSurfaces.count }, [1, 1])
        XCTAssertEqual(definitions.map { $0.continuingSurfaces[0].id },
                       ["live-activity-feature-a", "live-activity-feature-b"])
    }

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

    @MainActor
    func testFeatureARejectsForgedRoutingWithoutChangingBusinessState() async throws {
        let definition = try FeatureALiveIntegration.makeDefinition()
        try definition.externalAccess?.prepare(true)
        let store = try MiniAppSharedState<FeatureABusinessState>.shared(owner: FeatureALiveActivityService.owner)
        let before = try store.read()
        let service = try FeatureALiveActivityService.shared()
        let forged: [MiniAppContinuingIdentity] = [
            try .init(owner: MiniAppID("continuing-live-b"), localID: FeatureALiveActivityService.localID,
                      generation: before.generation),
            try .init(owner: FeatureALiveActivityService.owner, localID: "wrong", generation: before.generation),
            try .init(owner: FeatureALiveActivityService.owner, localID: FeatureALiveActivityService.localID,
                      generation: UUID()),
            try .init(owner: FeatureALiveActivityService.owner, localID: FeatureALiveActivityService.localID,
                      generation: before.generation, registrationID: UUID())]
        for identity in forged {
            await XCTAssertThrowsErrorAsync {
                try await service.advance(identity: identity, systemID: "forged-system")
            }
            XCTAssertEqual(try store.read().value.count, before.value.count)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) } catch {}
}
