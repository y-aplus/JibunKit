import Foundation
#if os(iOS)
import Observation
#endif

/// Coordinates cooperative Feature removal. This does not remove executable
/// code, revoke OS permissions, or sandbox code that bypasses its owner APIs.
#if os(iOS)
@Observable
#endif
@MainActor
public final class MiniAppManagement {
    public nonisolated static let defaultStorageKey = "jibunkit.feature-management.v1"
    public enum Status: String, Sendable {
        case enabled, disabling, disabled, removing, removed
    }

    public enum Stage: String, Sendable {
        case reservation, stopping, unregistering, deletingData, clearingConsent, enabling
    }

    public struct Failure: Error, Sendable {
        public let stage: Stage
        public let message: String
    }

    public enum Rejection: Error {
        case unknownOwner, busy, removalUnavailable, unfinishedRemoval
    }

    /// Cleanup must be idempotent: interrupted or failed operations can retry.
    /// The removal callback runs inside the owner's store reservation.
    public struct Registration: Sendable {
        public let id: MiniAppID
        public let lifetime: MiniAppFeatureLifetime?
        public let removal: MiniAppRemovalProvider?
        public let unregister: @MainActor @Sendable () async throws -> Void
        public let enable: @MainActor @Sendable () async throws -> Void

        public init(
            id: MiniAppID,
            lifetime: MiniAppFeatureLifetime? = nil,
            removal: MiniAppRemovalProvider? = nil,
            unregister: @escaping @MainActor @Sendable () async throws -> Void = {},
            enable: @escaping @MainActor @Sendable () async throws -> Void = {}
        ) {
            precondition(id.isValid && (lifetime == nil || lifetime?.id == id))
            precondition(removal == nil || removal?.id == id)
            self.id = id
            self.lifetime = lifetime
            self.removal = removal
            self.unregister = unregister
            self.enable = enable
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let coordinator: MiniAppRestoreCoordinator
    private let consents: MiniAppConsentStore
    private let registrations: [MiniAppID: Registration]
    private let onStatusChange: @MainActor (MiniAppID, Status) -> Void
    private var statuses: [MiniAppID: Status] = [:]
    public private(set) var failures: [MiniAppID: Failure] = [:]
    public private(set) var stages: [MiniAppID: Stage] = [:]

    public init(
        registrations: [Registration], defaults: UserDefaults,
        consents: MiniAppConsentStore,
        coordinator: MiniAppRestoreCoordinator = .shared,
        storageKey: String = MiniAppManagement.defaultStorageKey,
        onStatusChange: @escaping @MainActor (MiniAppID, Status) -> Void = { _, _ in }
    ) {
        precondition(Set(registrations.map(\.id)).count == registrations.count)
        self.registrations = Dictionary(uniqueKeysWithValues: registrations.map { ($0.id, $0) })
        self.defaults = defaults
        self.consents = consents
        self.coordinator = coordinator
        self.storageKey = storageKey
        self.onStatusChange = onStatusChange
        for registration in registrations {
            let status = Self.savedStatus(for: registration.id, defaults: defaults, storageKey: storageKey)
            statuses[registration.id] = status
            registration.lifetime?.setStartAllowed(status == .enabled)
            coordinator.setAccessAllowed(status == .enabled, for: registration.id)
        }
    }

    public func status(for id: MiniAppID) -> Status? { statuses[id] }
    public func isEnabled(_ id: MiniAppID) -> Bool { statuses[id] == .enabled }
    public func canRemove(_ id: MiniAppID) -> Bool { registrations[id]?.removal != nil }

    /// Read a point-in-time state from the same domain as the host, including
    /// from a Widget process. This is not a cross-process operation reservation.
    public nonisolated static func savedStatus(
        for id: MiniAppID, defaults: UserDefaults,
        storageKey: String = MiniAppManagement.defaultStorageKey
    ) -> Status {
        guard id.isValid else { return .disabling }
        guard let saved = defaults.object(forKey: storageKey + "." + id.rawValue) else { return .enabled }
        // Unknown/corrupt state cannot silently reactivate an owner.
        return (saved as? String).flatMap(Status.init(rawValue:)) ?? .disabling
    }

    public func disable(_ id: MiniAppID) async throws {
        guard statuses[id] != .removing && statuses[id] != .removed else {
            throw Rejection.unfinishedRemoval
        }
        try await deactivate(id, deleting: false)
    }

    /// Invoke only after confirming the displayed owner and data description.
    public func remove(_ id: MiniAppID) async throws {
        guard registrations[id]?.removal != nil else { throw Rejection.removalUnavailable }
        try await deactivate(id, deleting: true)
    }

    public func enable(_ id: MiniAppID) async throws {
        guard let registration = registrations[id] else { throw Rejection.unknownOwner }
        guard stages[id] == nil else { throw Rejection.busy }
        guard statuses[id] != .removing && statuses[id] != .disabling else {
            throw Rejection.unfinishedRemoval
        }
        guard statuses[id] != .enabled else { return }
        stages[id] = .enabling
        failures[id] = nil
        defer { stages[id] = nil }
        do {
            try Task.checkCancellation()
            try await registration.enable()
            // Re-enabling permits normal entry, but never starts business work.
            persist(.enabled, for: id)
            coordinator.setAccessAllowed(true, for: id)
            registration.lifetime?.setStartAllowed(true)
        } catch {
            let failure = Failure(stage: .enabling, message: String(describing: error))
            failures[id] = failure
            throw failure
        }
    }

    private func deactivate(_ id: MiniAppID, deleting: Bool) async throws {
        guard let registration = registrations[id] else { throw Rejection.unknownOwner }
        guard stages[id] == nil else { throw Rejection.busy }
        if statuses[id] == (deleting ? .removed : .disabled) { return }
        // Close admission before the first suspension. Persist intent so a
        // process exit cannot turn partially removed data into an active app.
        persist(deleting ? .removing : .disabling, for: id)
        registration.lifetime?.setStartAllowed(false)
        coordinator.setAccessAllowed(false, for: id)
        stages[id] = .reservation
        failures[id] = nil
        defer { stages[id] = nil }
        do {
            try await coordinator.withOwnerDeactivation(for: id) { [self] in
                try await self.performDeactivation(registration, deleting: deleting)
            }
            persist(deleting ? .removed : .disabled, for: id)
        } catch {
            let failure = Failure(stage: stages[id] ?? .reservation, message: String(describing: error))
            failures[id] = failure
            throw failure
        }
    }

    private func performDeactivation(_ registration: Registration, deleting: Bool) async throws {
        let id = registration.id
        stages[id] = .stopping
        await registration.lifetime?.stop()
        try Task.checkCancellation()
        stages[id] = .unregistering
        try await registration.unregister()
        if deleting {
            try Task.checkCancellation()
            stages[id] = .deletingData
            try await registration.removal?.removeData()
            stages[id] = .clearingConsent
            consents.removeConsents(for: id)
        }
    }

    private func persist(_ status: Status, for id: MiniAppID) {
        defaults.set(status.rawValue, forKey: storageKey + "." + id.rawValue)
        statuses[id] = status
        onStatusChange(id, status)
    }
}
