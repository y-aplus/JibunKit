import Foundation
import XCTest
import JibunKitCore

final class MiniAppManagementTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testDisableRetainsDataAndDeleteClearsOnlyOwnerThenReregistersFresh() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = MiniAppID("a"), b = MiniAppID("b")
        let store = ManagementData()
        let lifetimeA = MiniAppFeatureLifetime(id: a)
        let lifetimeB = MiniAppFeatureLifetime(id: b)
        let consents = MiniAppConsentStore(defaults: defaults)
        consents.setConsent(.allowed, for: a, permissionID: "camera")
        consents.setConsent(.denied, for: b, permissionID: "camera")
        let registrations = [
            MiniAppManagement.Registration(id: a, lifetime: lifetimeA,
                removal: MiniAppRemovalProvider(id: a, dataDescription: "A") { await store.removeA() },
                unregister: { await store.unregisterA() }),
            MiniAppManagement.Registration(id: b, lifetime: lifetimeB)
        ]
        let management = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents)
        let oldA = try await lifetimeA.start()
        let oldB = try await lifetimeB.start()
        try await management.disable(a)
        XCTAssertTrue(oldA.isClosed)
        XCTAssertFalse(oldB.isClosed)
        XCTAssertEqual(management.status(for: a), .disabled)
        let retained = await store.values
        XCTAssertEqual(retained, ["a": 7, "b": 9])
        XCTAssertEqual(consents.consent(for: a, permissionID: "camera"), .allowed)
        do { _ = try await lifetimeA.start(); XCTFail("disabled owner started") } catch {}
        try await management.enable(a)
        XCTAssertNil(lifetimeA.runtime, "Enabling must not start business work")
        _ = try await lifetimeA.start()
        try await management.remove(a)
        let removed = await store.values
        XCTAssertEqual(removed, ["b": 9])
        XCTAssertEqual(consents.consent(for: a, permissionID: "camera"), .notDetermined)
        XCTAssertEqual(consents.consent(for: b, permissionID: "camera"), .denied)
        let restarted = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents)
        XCTAssertEqual(restarted.status(for: a), .removed)
        XCTAssertFalse(lifetimeA.isStartAllowed)
        try await restarted.enable(a)
        XCTAssertEqual(restarted.status(for: a), .enabled)
        XCTAssertEqual(consents.consent(for: a, permissionID: "camera"), .notDetermined)
        XCTAssertTrue(lifetimeB.runtime === oldB)
        await lifetimeB.stop()
    }

    @MainActor
    func testFailedRemovalRemainsBlockedAcrossRestartAndRetryFinishes() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = MiniAppID("a")
        let lifetime = MiniAppFeatureLifetime(id: id)
        let store = ManagementData()
        let consents = MiniAppConsentStore(defaults: defaults)
        consents.setConsent(.allowed, for: id, permissionID: "camera")
        let registrations = [MiniAppManagement.Registration(id: id, lifetime: lifetime,
            removal: MiniAppRemovalProvider(id: id, dataDescription: "A") { try await store.removeAfterFirstFailure() })]
        let first = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents)
        _ = try await lifetime.start()
        do { try await first.remove(id); XCTFail("Expected deletion error") } catch {}
        XCTAssertEqual(first.status(for: id), .removing)
        XCTAssertEqual(first.failures[id]?.stage, .deletingData)
        XCTAssertEqual(consents.consent(for: id, permissionID: "camera"), .allowed)
        let restarted = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents)
        do { try await restarted.enable(id); XCTFail("Incomplete deletion became enabled") } catch {}
        try await restarted.remove(id)
        XCTAssertEqual(restarted.status(for: id), .removed)
        XCTAssertNil(restarted.failures[id])
        let values = await store.values
        XCTAssertEqual(values, ["b": 9])
    }

    @MainActor
    func testReservationConflictKeepsDataAndCanRetryWithoutRestartingOwner() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = MiniAppID("a")
        let coordinator = MiniAppRestoreCoordinator()
        let store = ManagementData()
        let lifetime = MiniAppFeatureLifetime(id: id)
        let manager = MiniAppManagement(registrations: [
            .init(id: id, lifetime: lifetime,
                  removal: .init(id: id, dataDescription: "A") { await store.removeA() })
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        let runtime = try await lifetime.start()
        try await coordinator.withStoreAccess(for: id) {
            do { try await manager.remove(id); XCTFail("Busy store was removed") } catch {}
        }
        XCTAssertEqual(manager.failures[id]?.stage, .reservation)
        XCTAssertFalse(runtime.isClosed)
        XCTAssertFalse(lifetime.isStartAllowed)
        let values = await store.values
        XCTAssertEqual(values["a"], 7)
        try await manager.remove(id)
        XCTAssertTrue(runtime.isClosed)
        XCTAssertEqual(manager.status(for: id), .removed)
    }
}

private actor ManagementData {
    enum Expected: Error { case firstRemoval }
    var values = ["a": 7, "b": 9]
    var failed = false
    var unregisters = 0
    func removeA() { values["a"] = nil }
    func unregisterA() { unregisters += 1 }
    func removeAfterFirstFailure() throws {
        if !failed { failed = true; throw Expected.firstRemoval }
        removeA()
    }
}
