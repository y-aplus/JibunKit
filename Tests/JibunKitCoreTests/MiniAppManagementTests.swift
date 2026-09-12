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
        let coordinator = MiniAppRestoreCoordinator()
        consents.setConsent(.allowed, for: a, permissionID: "camera")
        consents.setConsent(.denied, for: b, permissionID: "camera")
        let registrations = [
            MiniAppManagement.Registration(id: a, lifetime: lifetimeA,
                removal: MiniAppRemovalProvider(id: a, dataDescription: "A") { await store.removeA() },
                unregister: { await store.unregisterA() }),
            MiniAppManagement.Registration(id: b, lifetime: lifetimeB)
        ]
        let management = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents, coordinator: coordinator)
        try await lifetimeA.start()
        try await lifetimeB.start()
        let oldA = try XCTUnwrap(lifetimeA.runtime)
        let oldB = try XCTUnwrap(lifetimeB.runtime)
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
        let restarted = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents, coordinator: coordinator)
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
        let coordinator = MiniAppRestoreCoordinator()
        consents.setConsent(.allowed, for: id, permissionID: "camera")
        let registrations = [MiniAppManagement.Registration(id: id, lifetime: lifetime,
            removal: MiniAppRemovalProvider(id: id, dataDescription: "A") { try await store.removeAfterFirstFailure() })]
        let first = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents, coordinator: coordinator)
        _ = try await lifetime.start()
        do { try await first.remove(id); XCTFail("Expected deletion error") } catch {}
        XCTAssertEqual(first.status(for: id), .removing)
        XCTAssertEqual(first.failures[id]?.stage, .deletingData)
        XCTAssertEqual(consents.consent(for: id, permissionID: "camera"), .allowed)
        let restarted = MiniAppManagement(registrations: registrations, defaults: defaults, consents: consents, coordinator: coordinator)
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
        try await lifetime.start()
        let runtime = try XCTUnwrap(lifetime.runtime)
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
        do {
            try await coordinator.withStoreAccess(for: id) { await store.removeA() }
            XCTFail("Removed owner accepted normal store access")
        } catch is MiniAppRestoreCoordinator.Unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            try await coordinator.withStoreMaintenance(for: id) { await store.removeA() }
            XCTFail("Removed owner accepted maintenance from an old screen")
        } catch is MiniAppRestoreCoordinator.Unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        try await manager.enable(id)
        let reopened = try await coordinator.withStoreAccess(for: id) { await store.values }
        XCTAssertEqual(reopened, ["b": 9])
    }

    @MainActor
    func testPersistedInterruptedStateClosesStoreAdmissionBeforeFirstAwait() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = MiniAppID("a"), b = MiniAppID("b")
        defaults.set("unrecognized-state", forKey: "test-management.a")
        let coordinator = MiniAppRestoreCoordinator()
        let manager = MiniAppManagement(registrations: [.init(id: a), .init(id: b)],
            defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator,
            storageKey: "test-management")
        XCTAssertEqual(manager.status(for: a), .disabling)
        do {
            _ = try await coordinator.withStoreAccess(for: a) { 1 }
            XCTFail("Corrupt saved state silently enabled owner")
        } catch is MiniAppRestoreCoordinator.Unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        let other = try await coordinator.withStoreAccess(for: b) { 2 }
        XCTAssertEqual(other, 2)
        try await manager.disable(a)
        try await manager.enable(a)
        let recovered = try await coordinator.withStoreAccess(for: a) { 3 }
        XCTAssertEqual(recovered, 3)
    }

    @MainActor
    func testSeparateDefaultsReaderSeesOnlyChangedOwnerStatus() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let writer = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reader = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { writer.removePersistentDomain(forName: suite) }
        let a = MiniAppID("a"), b = MiniAppID("b")
        var observations: [MiniAppManagement.Status] = []
        let manager = MiniAppManagement(registrations: [.init(id: a), .init(id: b)],
            defaults: writer, consents: .init(defaults: writer), coordinator: .init(),
            onStatusChange: { id, status in
                XCTAssertEqual(id, a)
                XCTAssertEqual(MiniAppManagement.savedStatus(for: id, defaults: reader), status)
                observations.append(status)
            })
        try await manager.disable(a)
        XCTAssertEqual(MiniAppManagement.savedStatus(for: a, defaults: reader), .disabled)
        XCTAssertEqual(MiniAppManagement.savedStatus(for: b, defaults: reader), .enabled)
        try await manager.enable(a)
        XCTAssertEqual(observations, [.disabling, .disabled, .enabled])
        XCTAssertEqual(MiniAppManagement.savedStatus(for: a, defaults: reader), .enabled)
    }

    @MainActor
    func testUnregisterFailureKeepsStoredDataUntilSuccessfulRetry() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = MiniAppID("a")
        let data = ManagementData()
        let manager = MiniAppManagement(registrations: [
            .init(id: id, removal: .init(id: id, dataDescription: "A") { await data.removeA() },
                  unregister: { try await data.unregisterAfterFirstFailure() })
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: .init())
        do { try await manager.remove(id); XCTFail("Expected unregister failure") } catch {}
        XCTAssertEqual(manager.status(for: id), .removing)
        XCTAssertEqual(manager.failures[id]?.stage, .unregistering)
        let afterFailure = await data.values
        XCTAssertEqual(afterFailure, ["a": 7, "b": 9])
        try await manager.remove(id)
        let afterRetry = await data.values
        XCTAssertEqual(afterRetry, ["b": 9])
        XCTAssertEqual(manager.status(for: id), .removed)
    }

    @MainActor
    func testRemovalWaitsForOwnedWorkBeforeUnregisteringOrDeleting() async throws {
        let suite = "MiniAppManagementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = MiniAppID("a"), b = MiniAppID("b")
        let entered = expectation(description: "Owned work started")
        let cancelled = expectation(description: "Owned work received cancellation")
        let gate = ManagementStopGate()
        let data = ManagementData()
        let lifetime = MiniAppFeatureLifetime(id: a) { runtime in
            try runtime.start {
                await withTaskCancellationHandler {
                    await gate.wait(entered: entered)
                } onCancel: { cancelled.fulfill() }
            }
        }
        let other = MiniAppFeatureLifetime(id: b)
        let coordinator = MiniAppRestoreCoordinator()
        let manager = MiniAppManagement(registrations: [
            .init(id: a, lifetime: lifetime,
                  removal: .init(id: a, dataDescription: "A") { await data.removeA() },
                  unregister: { await data.unregisterA() }),
            .init(id: b, lifetime: other)
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        try await lifetime.start()
        try await other.start()
        await fulfillment(of: [entered], timeout: 5)
        let removal = Task { try await manager.remove(a) }
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertEqual(manager.stages[a], .stopping)
        XCTAssertEqual(manager.status(for: a), .removing)
        let pendingValues = await data.values
        let pendingUnregisters = await data.unregisters
        XCTAssertEqual(pendingValues, ["a": 7, "b": 9])
        XCTAssertEqual(pendingUnregisters, 0)
        let otherValue = try await coordinator.withStoreAccess(for: b) { await data.values["b"] }
        XCTAssertEqual(otherValue, 9)
        XCTAssertFalse(try XCTUnwrap(other.runtime).isClosed)
        await gate.release()
        try await removal.value
        XCTAssertEqual(manager.status(for: a), .removed)
        let finalValues = await data.values
        let finalUnregisters = await data.unregisters
        XCTAssertEqual(finalValues, ["b": 9])
        XCTAssertEqual(finalUnregisters, 1)
        await other.stop()
    }
}

private actor ManagementData {
    enum Expected: Error { case firstRemoval }
    var values = ["a": 7, "b": 9]
    var failed = false
    var unregisters = 0
    func removeA() { values["a"] = nil }
    func unregisterA() { unregisters += 1 }
    func unregisterAfterFirstFailure() throws {
        unregisters += 1
        if !failed { failed = true; throw Expected.firstRemoval }
    }
    func removeAfterFirstFailure() throws {
        if !failed { failed = true; throw Expected.firstRemoval }
        removeA()
    }
}

private actor ManagementStopGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(entered: XCTestExpectation) async {
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
