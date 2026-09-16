import Foundation
import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppContinuingSurfaceTests: XCTestCase, @unchecked Sendable {
    private enum Injected: Error { case failure }
    private let a = MiniAppID("surface-a"), b = MiniAppID("surface-b")

    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testJournalRecoversPendingRecordAndKeepsForeignOwnerBytesOnFailure() throws {
        let root = directory()
        let first = try MiniAppContinuingJournal(owner: a, namespace: "alarms", containerURL: root)
        let second = try MiniAppContinuingJournal(owner: b, namespace: "alarms", containerURL: root)
        let key = try MiniAppContinuingIdentity(owner: a, localID: "same/id", generation: UUID())
        let other = try MiniAppContinuingIdentity(owner: b, localID: "same/id", generation: UUID())
        try first.update { $0.append(.init(identity: key, systemID: UUID().uuidString)) }
        try second.update { $0.append(.init(identity: other, systemID: "native-b", phase: .active)) }
        let bURL = root.appendingPathComponent("Library/Application Support/JibunKit/ContinuingSurfaces/surface-b/alarms.json")
        let beforeB = try Data(contentsOf: bURL)
        let reconstructed = try MiniAppContinuingJournal(owner: a, namespace: "alarms", containerURL: root)
        XCTAssertEqual(try reconstructed.read().first?.phase, .starting)
        XCTAssertThrowsError(try first.update { records in
            records.removeAll()
            throw Injected.failure
        })
        XCTAssertEqual(try first.read().first?.identity, key)
        XCTAssertThrowsError(try first.update { $0.append(.init(identity: other)) })
        XCTAssertEqual(try first.read().count, 1)
        XCTAssertEqual(try Data(contentsOf: bURL), beforeB)
        let live = try MiniAppContinuingJournal(owner: a, namespace: "live-activities", containerURL: root)
        XCTAssertTrue(try live.read().isEmpty)
        XCTAssertEqual(try first.read().count, 1)
    }

    func testJournalRejectsDuplicateIdentityAndCorruptionWithoutTreatingItAsEmpty() throws {
        let root = directory()
        let journal = try MiniAppContinuingJournal(owner: a, namespace: "alarm", containerURL: root)
        let key = try MiniAppContinuingIdentity(owner: a, localID: "same", generation: UUID())
        try journal.update { $0.append(.init(identity: key)) }
        XCTAssertThrowsError(try journal.update { $0.append(.init(identity: key)) })
        let url = root.appendingPathComponent("Library/Application Support/JibunKit/ContinuingSurfaces/surface-a/alarm.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try journal.read())
        XCTAssertThrowsError(try journal.update { $0.removeAll() })
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testGateSerializesAcrossSuspensionAndMaintenanceWorksAfterClose() async throws {
        let gate = MiniAppContinuingOperationGate()
        let probe = OperationProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await gate.perform {
                        await probe.begin()
                        await Task.yield()
                        await probe.end()
                    }
                }
            }
            try await group.waitForAll()
        }
        let maximum = await probe.maximum
        XCTAssertEqual(maximum, 1, "Actor reentrancy must not overlap native calls")
        await gate.close()
        do { try await gate.perform { await probe.begin() }; XCTFail("Closed admission accepted work") }
        catch { XCTAssertEqual(error as? MiniAppContinuingError, .admissionClosed) }
        try await gate.performMaintenance { await probe.record("cleanup") }
        await gate.open()
        try await gate.perform { await probe.record("fresh") }
        let events = await probe.events
        XCTAssertEqual(events, ["cleanup", "fresh"])
    }

    func testGateDrainsBeforeCloseCompletesAndRejectsCancelledCall() async throws {
        let gate = MiniAppContinuingOperationGate()
        let began = TestSignal(), finish = TestSignal(), probe = OperationProbe()
        let operation = Task {
            try await gate.perform {
                await began.signal()
                await finish.wait()
                await probe.record("finished")
            }
        }
        await began.wait()
        let close = Task { await gate.close(); await probe.record("closed") }
        await finish.signal()
        try await operation.value
        await close.value
        let events = await probe.events
        XCTAssertEqual(events, ["finished", "closed"])
        await gate.open()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await gate.perform { await probe.record("incorrect") }
        }
        do { try await cancelled.value; XCTFail("Cancelled native operation ran") } catch is CancellationError {}
        let after = await probe.events
        XCTAssertEqual(after, events)
    }

    @MainActor
    func testFailedRemovalKeepsJournalAndOtherOwnerThenRetryFinishes() async throws {
        let root = directory()
        let stateA = try MiniAppSharedState<Int>(owner: a, containerURL: root)
        let stateB = try MiniAppSharedState<Int>(owner: b, containerURL: root)
        let nativeA = FakeSurface(), nativeB = FakeSurface()
        await nativeA.failEnd(true)
        let groupA = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [nativeA.surface(owner: a)])
        let groupB = MiniAppContinuingSurfaceGroup(owner: b, surfaces: [nativeB.surface(owner: b)])
        let suite = "ContinuingSurfaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registrations: [MiniAppManagement.Registration] = [
            .init(id: a, removal: .init(id: a, dataDescription: "A") { try stateA.remove() },
                externalAccess: groupA.wrapping(stateA.externalAccess(initialValue: 10)),
                unregister: { try await groupA.endOwned() }),
            .init(id: b, externalAccess: groupB.wrapping(stateB.externalAccess(initialValue: 20)),
                unregister: { try await groupB.endOwned() })
        ]
        let manager = MiniAppManagement(registrations: registrations, defaults: defaults,
            consents: .init(defaults: defaults), coordinator: MiniAppRestoreCoordinator())
        let bGeneration = try stateB.read().generation
        do { try await manager.remove(a); XCTFail("OS failure appeared complete") } catch {}
        XCTAssertEqual(manager.status(for: a), .removing)
        XCTAssertEqual(manager.failures[a]?.stage, .unregistering)
        XCTAssertThrowsError(try stateA.read())
        let aActive = await nativeA.active
        XCTAssertTrue(aActive)
        XCTAssertEqual(try stateB.read().generation, bGeneration)
        XCTAssertEqual(try stateB.read().value, 20)
        let bEvents = await nativeB.events
        XCTAssertTrue(bEvents.isEmpty)
        await nativeA.failEnd(false)
        try await manager.remove(a)
        XCTAssertEqual(manager.status(for: a), .removed)
        try await manager.enable(a)
        XCTAssertEqual(try stateA.read().value, 10)
        let afterEnable = await nativeA.active
        XCTAssertFalse(afterEnable, "Enable must not restart an OS surface")
    }

    func testRestoreEndsBeforeApplyChangesGenerationAndDoesNotRestart() async throws {
        let root = directory()
        let state = try MiniAppSharedState<Int>(owner: a, containerURL: root)
        let other = try MiniAppSharedState<Int>(owner: b, containerURL: root)
        let native = FakeSurface()
        let group = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [native.surface(owner: a)])
        let access = group.wrapping(state.externalAccess(initialValue: 10))
        try access.prepare(true)
        try other.initialize(20, enabled: true)
        let oldGeneration = try state.read().generation
        let lifecycle = access.restoreLifecycle(nil)
        try await lifecycle.perform {
            let active = await native.active
            XCTAssertFalse(active)
            XCTAssertThrowsError(try state.read(), "Maintenance must precede business replacement")
            try state.replaceForRestore(40)
        }
        XCTAssertEqual(try state.read().value, 40)
        XCTAssertThrowsError(try state.update(generation: oldGeneration) { $0 = 999 })
        XCTAssertEqual(try other.read().value, 20)
        let active = await native.active
        XCTAssertFalse(active)
        let events = await native.events
        XCTAssertEqual(events, ["close", "end", "reconcile", "open"])
    }

    func testFailedRestoreStopPreservesDataRecoversAdmissionAndAttemptsOtherSurfaces() async throws {
        let state = try MiniAppSharedState<Int>(owner: a, containerURL: directory())
        let failing = FakeSurface(), second = FakeSurface()
        await failing.failEnd(true)
        let group = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [
            failing.surface(owner: a, id: "first"), second.surface(owner: a, id: "second")
        ])
        let access = group.wrapping(state.externalAccess(initialValue: 10))
        try access.prepare(true)
        let generation = try state.read().generation
        do {
            try await access.restoreLifecycle(nil).perform {
                try state.replaceForRestore(99)
                XCTFail("Apply executed despite failed OS cleanup")
            }
            XCTFail("Restore failure was swallowed")
        } catch {}
        XCTAssertEqual(try state.read().generation, generation)
        XCTAssertEqual(try state.read().value, 10)
        let secondActive = await second.active
        XCTAssertFalse(secondActive, "One failing surface must not skip cleanup of its sibling")
        let events = await failing.events
        XCTAssertEqual(events.suffix(2), ["reconcile", "open"])
    }

    func testCloseFailureStillPersistsRejectionAndClosesSiblingSurface() async throws {
        let state = try MiniAppSharedState<Int>(owner: a, containerURL: directory())
        let sibling = FakeSurface()
        let failure = MiniAppContinuingSurface(owner: a, id: "failing",
            close: { throw Injected.failure }, reconcile: {}, endOwned: {}, open: {})
        let group = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [failure, sibling.surface(owner: a)])
        let access = group.wrapping(state.externalAccess(initialValue: 10))
        try access.prepare(true)
        do { try await access.close(); XCTFail("Close failure swallowed") } catch {}
        XCTAssertThrowsError(try state.read(), "A failed native close must still persist rejection")
        let events = await sibling.events
        XCTAssertEqual(events, ["close"])
    }

    func testManagementDisableDuringRestoreIsNotUndoneByResume() async throws {
        let state = try MiniAppSharedState<Int>(owner: a, containerURL: directory())
        let native = FakeSurface()
        let group = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [native.surface(owner: a)])
        let access = group.wrapping(state.externalAccess(initialValue: 10))
        try access.prepare(true)
        let lifecycle = access.restoreLifecycle(nil)
        try await lifecycle.stop()
        try state.replaceForRestore(40)
        // Management can close admission before obtaining the restore reservation.
        try await access.close()
        try await lifecycle.resume()
        XCTAssertThrowsError(try state.read())
        let active = await native.active
        XCTAssertFalse(active)
        try await access.open() // Explicit management re-enable is a separate operation.
        XCTAssertEqual(try state.read().value, 40)
    }

    func testFailedInnerRecoveryDoesNotReopenNativeAdmission() async throws {
        let state = try MiniAppSharedState<Int>(owner: a, containerURL: directory())
        let native = FakeSurface()
        let group = MiniAppContinuingSurfaceGroup(owner: a, surfaces: [native.surface(owner: a)])
        let access = group.wrapping(state.externalAccess(initialValue: 10))
        try access.prepare(true)
        let inner = MiniAppRestoreLifecycle(stop: { throw Injected.failure }, resume: {},
            recoverAfterFailedStop: { throw Injected.failure })
        do {
            try await access.restoreLifecycle(inner).perform { XCTFail("Apply after failed stop") }
            XCTFail("Recovery failure swallowed")
        } catch {}
        XCTAssertThrowsError(try state.read(), "Unrecovered maintenance remains closed")
        let events = await native.events
        XCTAssertEqual(events, ["close"])
    }
}

private actor FakeSurface {
    let gate = MiniAppContinuingOperationGate()
    var active = true
    var shouldFailEnd = false
    var events: [String] = []
    func failEnd(_ value: Bool) { shouldFailEnd = value }
    func record(_ value: String) { events.append(value) }
    func end() throws {
        events.append("end")
        if shouldFailEnd { throw Failure.injected }
        active = false
    }
    enum Failure: Error { case injected }
    nonisolated func surface(owner: MiniAppID, id: String = "native") -> MiniAppContinuingSurface {
        .init(owner: owner, id: id, close: { [self] in
            await gate.close()
            await record("close")
        }, reconcile: { [self] in
            try await gate.performMaintenance { await self.record("reconcile") }
        }, endOwned: { [self] in
            try await gate.performMaintenance { try await self.end() }
        }, open: { [self] in
            await record("open")
            await gate.open()
        })
    }
}

private actor OperationProbe {
    var running = 0
    var maximum = 0
    var events: [String] = []
    func begin() { running += 1; maximum = max(maximum, running) }
    func end() { running -= 1 }
    func record(_ event: String) { events.append(event) }
}

private actor TestSignal {
    var signalled = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
#endif
