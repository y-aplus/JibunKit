import ContinuingAlarmFeatureA
import ContinuingAlarmFeatureB
import Foundation
import JibunKitCore
import XCTest

@MainActor
final class ContinuingAlarmNativeTests: XCTestCase {
    func testDefinitionFactoriesExposeCompleteIndependentIntegration() throws {
        let a = try FeatureAAlarmIntegration.makeDefinition()
        let b = try FeatureBAlarmIntegration.makeDefinition()
        XCTAssertNotNil(a.backup); XCTAssertNotNil(a.removal); XCTAssertNotNil(a.externalAccess)
        XCTAssertNotNil(b.backup); XCTAssertNotNil(b.removal); XCTAssertNotNil(b.externalAccess)
        XCTAssertEqual(a.continuingSurfaces.map(\.id), ["alarmkit"])
        XCTAssertEqual(b.continuingSurfaces.map(\.id), ["alarmkit"])
        XCTAssertEqual(a.id, FeatureAAlarmModel.owner)
        XCTAssertEqual(b.id, FeatureBAlarmModel.owner)
    }

    func testAServiceRejectsEveryStaleCallbackBeforeBusinessMutation() async throws {
        _ = try FeatureAAlarmIntegration.makeDefinition()
        _ = try FeatureBAlarmIntegration.makeDefinition()
        let service = try FeatureAAlarmEnvironment.shared.service()
        let serviceB = try FeatureBAlarmEnvironment.shared.service()
        let snapshot = try service.store.read()
        let identity = try MiniAppContinuingIdentity(owner: FeatureAAlarmModel.owner,
            localID: FeatureAAlarmModel.localID, generation: snapshot.generation)
        let systemID = UUID()
        let journal = try MiniAppContinuingJournal.shared(owner: FeatureAAlarmModel.owner, namespace: "alarmkit")
        try journal.update { $0 = [.init(identity: identity, systemID: systemID.uuidString, phase: .active)] }
        defer { try? journal.update { $0 = [] } }
        let before = try JSONEncoder().encode(service.store.read().value)
        let bBefore = try JSONEncoder().encode(serviceB.store.read().value)

        let inputs = [
            try MiniAppContinuingIdentity(owner: FeatureBAlarmModel.owner, localID: identity.localID,
                generation: identity.generation, registrationID: identity.registrationID),
            try MiniAppContinuingIdentity(owner: FeatureAAlarmModel.owner, localID: "wrong-local",
                generation: identity.generation, registrationID: identity.registrationID),
            try MiniAppContinuingIdentity(owner: FeatureAAlarmModel.owner, localID: identity.localID,
                generation: UUID(), registrationID: identity.registrationID),
            try MiniAppContinuingIdentity(owner: FeatureAAlarmModel.owner, localID: identity.localID,
                generation: identity.generation, registrationID: UUID()),
        ]
        for input in inputs {
            do { try await service.handleSystemStop(identity: input, systemID: systemID); XCTFail("stale callback accepted") }
            catch {}
            XCTAssertEqual(try JSONEncoder().encode(service.store.read().value), before)
            XCTAssertEqual(try JSONEncoder().encode(serviceB.store.read().value), bBefore)
        }
        do { try await service.handleSystemStop(identity: identity, systemID: UUID()); XCTFail("wrong system ID accepted") }
        catch {}
        XCTAssertEqual(try JSONEncoder().encode(service.store.read().value), before)
        XCTAssertEqual(try JSONEncoder().encode(serviceB.store.read().value), bBefore)
    }
}
