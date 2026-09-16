import ContinuingFeatureA
import ContinuingFeatureB
import ContinuingAlarmFeatureA
import ContinuingAlarmFeatureB
import Foundation
import JibunKitCore
import XCTest

/// Real Feature stores/providers and management/restore composition. No OS
/// activity is started: OS rendering, scheduling and buttons remain device evidence.
@MainActor
final class ContinuingStateNativeTests: XCTestCase {
    private struct Snapshot: Equatable {
        let bytes: Data
        let generation: UUID
    }

    private struct Owner {
        let definition: MiniAppDefinition
        let initial: Data
        let read: @MainActor () throws -> Snapshot
        let write: @MainActor (UUID, Int) throws -> Void
    }

    private func owner<Value: Codable & Sendable>(
        _ definition: MiniAppDefinition, initial: Value, field: WritableKeyPath<Value, Int>
    ) throws -> Owner {
        let store = try MiniAppSharedState<Value>.shared(owner: definition.id)
        return Owner(definition: definition, initial: try encoded(initial), read: {
            let value = try store.read()
            return Snapshot(bytes: try Self.encodedValue(value.value), generation: value.generation)
        }, write: { generation, number in
            try store.update(generation: generation) { $0[keyPath: field] = number }
        })
    }

    private static func encodedValue<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        try Self.encodedValue(value)
    }

    func testRealFeatureManagementAndJSONRestorePreserveOtherOwners() async throws {
        let owners = try [
            owner(FeatureALiveIntegration.makeDefinition(), initial: FeatureABusinessState.initial, field: \.count),
            owner(FeatureBLiveIntegration.makeDefinition(), initial: FeatureBBusinessState.initial, field: \.score),
            owner(FeatureAAlarmIntegration.makeDefinition(), initial: FeatureAAlarmState.initial, field: \.stopEvents),
            owner(FeatureBAlarmIntegration.makeDefinition(), initial: FeatureBAlarmState.initial, field: \.stopEvents),
        ]
        let suite = "ContinuingStateNativeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = MiniAppRestoreCoordinator()
        // Use the same public composition as the host, excluding unrelated
        // Spotlight/notification cleanup already covered by host UI regression.
        let management = MiniAppManagement(registrations: owners.map { owner in
            let definition = owner.definition
            let surfaces = definition.continuingSurfaceGroup
            return .init(id: definition.id, removal: definition.removal,
                externalAccess: definition.effectiveExternalAccess,
                unregister: { try await surfaces.endOwned() })
        }, defaults: defaults, consents: .init(defaults: defaults), coordinator: coordinator)

        // A preceding UI run may have left a tombstone. Explicitly re-register
        // each test owner; normal startup itself must never erase old data.
        for owner in owners {
            try await management.remove(owner.definition.id)
            try await management.enable(owner.definition.id)
        }
        for (owner, value) in zip(owners, [17, 237, 3, 9]) {
            try owner.write(owner.read().generation, value)
        }

        for index in [0, 2] {
            let a = owners[index]
            let id = a.definition.id
            let before = try owners.map { try $0.read() }
            @MainActor func checkOtherOwners(_ stage: String) throws {
                for other in owners.indices where other != index {
                    XCTAssertEqual(try owners[other].read(), before[other],
                        "\(stage): \(owners[other].definition.id.rawValue) value/generation changed")
                }
            }

            try await management.disable(id)
            XCTAssertThrowsError(try a.read())
            XCTAssertThrowsError(try a.write(before[index].generation, 999))
            try checkOtherOwners("disabled")
            try await management.enable(id)
            XCTAssertEqual(try a.read(), before[index])
            try checkOtherOwners("re-enabled")

            let providers = try owners.map { try XCTUnwrap($0.definition.backup) }
            var entries: [MiniAppBackupEntry] = []
            for provider in providers { entries.append(try await provider.exportEntry(coordinator: coordinator)) }
            let json = try MiniAppBackup(entries: entries).encoded()
            let backup = try MiniAppBackup.decode(json)
            try a.write(before[index].generation, 901)
            let changed = try a.read()
            XCTAssertNotEqual(changed.bytes, before[index].bytes)
            let malformed = MiniAppBackupEntry(id: id, schemaVersion: 1, payload: Data("{".utf8))
            XCTAssertThrowsError(try providers[index].prepareRestore(malformed))
            XCTAssertEqual(try a.read(), changed)
            try checkOtherOwners("invalid restore rejected")

            let plan = try MiniAppRestorePlan(backup: backup, selected: [id], providers: providers)
            XCTAssertEqual(plan.ids, [id])
            let lifecycle = try XCTUnwrap(a.definition.effectiveRestoreLifecycle)
            try await plan.apply(lifecycles: [id: lifecycle], coordinator: coordinator)
            let restored = try a.read()
            XCTAssertEqual(restored.bytes, before[index].bytes)
            XCTAssertNotEqual(restored.generation, before[index].generation)
            XCTAssertThrowsError(try a.write(before[index].generation, 999))
            try checkOtherOwners("selected JSON restore")

            try await management.remove(id)
            XCTAssertThrowsError(try a.read())
            try checkOtherOwners("deleted")
            try await management.enable(id)
            XCTAssertEqual(try a.read().bytes, a.initial)
            XCTAssertNotEqual(try a.read().generation, restored.generation)
            XCTAssertThrowsError(try a.write(restored.generation, 999))
            try checkOtherOwners("re-registered")
            if index == 0 {
                let activity = try await FeatureALiveActivityService.shared().currentDescriptor()
                XCTAssertNil(activity, "Management must not start a Live Activity")
            } else {
                let alarm = try await FeatureAAlarmEnvironment.shared.service().current()
                XCTAssertNil(alarm, "Management must not schedule an alarm")
            }
        }

        let retained = try owners.map { try $0.read() }
        let recreated = try [FeatureALiveIntegration.makeDefinition(), FeatureBLiveIntegration.makeDefinition(),
                             FeatureAAlarmIntegration.makeDefinition(), FeatureBAlarmIntegration.makeDefinition()]
        for definition in recreated { try definition.effectiveExternalAccess?.prepare(true) }
        XCTAssertEqual(try owners.map { try $0.read() }, retained, "Bootstrap replaced persisted state")
        // Leave these disposable simulator owners enabled for the UI test.
    }
}
