import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppSharedStateManagementTests: XCTestCase, @unchecked Sendable {
    private enum Expected: Error { case stop, resume, apply }

    @MainActor
    private func fixture() throws -> (MiniAppSharedState<Int>, MiniAppSharedState<Int>, MiniAppManagement, MiniAppRestoreCoordinator, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SharedManagement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let a = try MiniAppSharedState<Int>(owner: MiniAppID("a"), containerURL: root)
        let b = try MiniAppSharedState<Int>(owner: MiniAppID("b"), containerURL: root)
        let coordinator = MiniAppRestoreCoordinator()
        let manager = MiniAppManagement(registrations: [registration(a, initial: 10), registration(b, initial: 20)],
            defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        addTeardownBlock {
            try FileManager.default.removeItem(at: root)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        return (a, b, manager, coordinator, defaults)
    }

    @MainActor
    private func registration(_ store: MiniAppSharedState<Int>, initial: Int) -> MiniAppManagement.Registration {
        .init(id: store.owner, removal: .init(id: store.owner, dataDescription: "Owned shared state") { try store.remove() },
              externalAccess: store.externalAccess(initialValue: initial))
    }

    @MainActor
    func testNormalManagementRetainsThenRemovesAndExplicitlyReregistersOnlyA() async throws {
        let (a, b, manager, _, _) = try fixture()
        let old = try a.read()
        try a.update(generation: old.generation) { $0 = 13 }
        try await manager.disable(a.owner)
        XCTAssertThrowsError(try a.update(generation: old.generation) { $0 += 1 })
        try await manager.enable(a.owner)
        XCTAssertEqual(try a.read().value, 13)
        try await manager.remove(a.owner)
        try a.initialize(999, enabled: true)
        XCTAssertThrowsError(try a.read())
        try await manager.enable(a.owner)
        XCTAssertEqual(try a.read().value, 10)
        XCTAssertThrowsError(try a.update(generation: old.generation) { $0 = 999 })
        XCTAssertEqual(try b.read().value, 20)
    }

    @MainActor
    func testRestoreCompletionCannotReopenConcurrentManagementDisable() async throws {
        let (a, b, manager, coordinator, _) = try fixture()
        let lifecycle = a.externalAccess(initialValue: 10).restoreLifecycle(nil)
        try await coordinator.withStoreMaintenance(for: a.owner, lifecycle: lifecycle) {
            XCTAssertThrowsError(try a.read())
            // The management operation closes external admission even though
            // this active restore prevents its exclusive cleanup reservation.
            do { try await manager.disable(a.owner); XCTFail("Expected reservation conflict") } catch {}
            try a.replaceForRestore(41)
            XCTAssertEqual(try b.read().value, 20)
        }
        XCTAssertThrowsError(try a.read(), "Restore resume must not undo disable")
        XCTAssertEqual(manager.status(for: a.owner), .disabling)
        try await manager.disable(a.owner)
        try await manager.enable(a.owner)
        XCTAssertEqual(try a.read().value, 41)
    }

    @MainActor
    func testSelectedRestoreRotatesGenerationAndFailedApplyPreservesOtherOwner() async throws {
        let (a, b, _, coordinator, _) = try fixture()
        let old = try a.read()
        let plan = try MiniAppRestorePlan(prepared: [a.owner: .init { try a.replaceForRestore(42) }])
        let access = a.externalAccess(initialValue: 10)
        try await plan.apply(lifecycles: [a.owner: access.restoreLifecycle(nil)], coordinator: coordinator)
        XCTAssertEqual(try a.read().value, 42)
        XCTAssertThrowsError(try a.update(generation: old.generation) { $0 = 0 })
        let failed = try MiniAppRestorePlan(prepared: [a.owner: .init { throw Expected.apply }])
        do { try await failed.apply(lifecycles: [a.owner: access.restoreLifecycle(nil)], coordinator: coordinator); XCTFail() }
        catch let failure as MiniAppRestoreFailure { XCTAssertEqual(failure.stage, .apply) }
        XCTAssertEqual(try a.read().value, 42)
        XCTAssertEqual(try b.read().value, 20)
    }

    @MainActor
    func testFailedStopReleasesOwnLeaseAndFailedAcquisitionDoesNotReleaseAnother() async throws {
        let (a, _, _, coordinator, _) = try fixture()
        let access = a.externalAccess(initialValue: 10)
        let failing = access.restoreLifecycle(.init(stop: { throw Expected.stop }, resume: {}))
        do { try await coordinator.withStoreMaintenance(for: a.owner, lifecycle: failing) { XCTFail("Applied after stop failure") }; XCTFail() }
        catch {}
        XCTAssertEqual(try a.read().value, 10)
        let first = access.restoreLifecycle(nil)
        let second = access.restoreLifecycle(nil)
        try await first.stop()
        do { try await second.perform {}; XCTFail("Acquired another live lease") } catch {}
        XCTAssertThrowsError(try a.read(), "Failed acquisition recovery must not release the first lease")
        try await first.resume()
        XCTAssertEqual(try a.read().value, 10)
    }

    @MainActor
    func testFailedResumeSurvivesRestartAndExplicitManagementRecoveryKeepsData() async throws {
        let (a, b, _, coordinator, defaults) = try fixture()
        let lifecycle = a.externalAccess(initialValue: 10).restoreLifecycle(.init(stop: {}, resume: { throw Expected.resume }))
        do { try await coordinator.withStoreMaintenance(for: a.owner, lifecycle: lifecycle) { try a.replaceForRestore(44) }; XCTFail() }
        catch is MiniAppRestoreLifecycle.Failure {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertThrowsError(try a.read())
        let restarted = MiniAppManagement(registrations: [registration(a, initial: 10), registration(b, initial: 20)],
            defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        XCTAssertEqual(restarted.status(for: a.owner), .disabling)
        XCTAssertEqual(restarted.failures[a.owner]?.stage, .externalAccess)
        XCTAssertTrue(restarted.isEnabled(b.owner))
        try await restarted.disable(a.owner)
        try await restarted.enable(a.owner)
        XCTAssertEqual(try a.read().value, 44)
        XCTAssertEqual(try b.read().value, 20)
    }

    @MainActor
    func testPersistedDisabledOwnerNeverSilentlyReopensAtBootstrap() async throws {
        let (a, b, manager, coordinator, defaults) = try fixture()
        try await manager.disable(a.owner)
        let restarted = MiniAppManagement(registrations: [registration(a, initial: 10), registration(b, initial: 20)],
            defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        XCTAssertFalse(restarted.isEnabled(a.owner))
        XCTAssertThrowsError(try a.read())
        XCTAssertEqual(try b.read().value, 20)
    }

    @MainActor
    func testExternalCloseFailurePreventsDeletionAndRetriesWithoutTouchingB() async throws {
        let (a, b, _, coordinator, defaults) = try fixture()
        let access = a.externalAccess(initialValue: 10)
        let attempts = ExternalAttempts()
        let faulty = MiniAppExternalAccess(id: a.owner, prepare: access.prepare, close: {
            if await attempts.next() == 1 { throw Expected.stop }
            try await access.close()
        }, open: access.open, restoreLifecycle: access.restoreLifecycle)
        let manager = MiniAppManagement(registrations: [
            .init(id: a.owner, removal: .init(id: a.owner, dataDescription: "A") { try a.remove() }, externalAccess: faulty),
            registration(b, initial: 20)
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        do { try await manager.remove(a.owner); XCTFail() } catch {}
        XCTAssertEqual(manager.failures[a.owner]?.stage, .externalAccess)
        XCTAssertEqual(manager.status(for: a.owner), .removing)
        XCTAssertEqual(try a.read().value, 10, "A failed close is reported; deletion must not start")
        try await manager.remove(a.owner)
        XCTAssertThrowsError(try a.read())
        XCTAssertEqual(manager.status(for: a.owner), .removed)
        XCTAssertEqual(try b.read().value, 20)
    }

    @MainActor
    func testFailedExternalEnableClosesAdmissionAndUndoesNativeRegistration() async throws {
        let (a, b, first, coordinator, defaults) = try fixture()
        try await first.disable(a.owner)
        let access = a.externalAccess(initialValue: 10)
        let cleanup = ExternalAttempts()
        let faulty = MiniAppExternalAccess(id: a.owner, prepare: access.prepare, close: access.close, open: {
            try await access.open()
            throw Expected.resume
        }, restoreLifecycle: access.restoreLifecycle)
        let manager = MiniAppManagement(registrations: [
            .init(id: a.owner, externalAccess: faulty, unregister: { _ = await cleanup.next() })
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)
        do { try await manager.enable(a.owner); XCTFail() } catch {}
        XCTAssertEqual(manager.failures[a.owner]?.stage, .enabling)
        XCTAssertEqual(manager.status(for: a.owner), .disabled)
        XCTAssertThrowsError(try a.read())
        let calls = await cleanup.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try b.read().value, 20)
    }
}

private actor ExternalAttempts {
    var count = 0
    func next() -> Int { count += 1; return count }
}
#endif
