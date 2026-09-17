import Foundation

/// The server-side identity used by one Feature. APNs device tokens remain an
/// app-level value and are never presented as a Feature-owned token.
public struct MiniAppRemotePushIdentity: Sendable, Equatable, Hashable {
    public let server: String
    public let account: String

    public init(server: String, account: String) throws {
        guard !server.isEmpty, !account.isEmpty else { throw MiniAppRemotePushFailure.invalidIdentity }
        self.server = server
        self.account = account
    }
}

public enum MiniAppRemotePushFailure: Error, Sendable, Equatable {
    case invalidIdentity
    case ownerMismatch
    case notConnected
    case staleGeneration
}

public enum MiniAppRemotePushRegistrationEvent: Sendable, Equatable {
    case tokenChanged(token: Data, identity: MiniAppRemotePushIdentity, generation: UUID)
    case registrationFailed(message: String, generation: UUID)
    case ownerUnregistered(identity: MiniAppRemotePushIdentity)
}

public enum MiniAppRemotePushFetchResult: Int, Sendable, Equatable {
    case noData = 0
    case newData = 1
    case failed = 2
}

public struct MiniAppRemotePushMessage: Sendable, Equatable {
    public let owner: MiniAppID
    public let destination: String?
    /// A property-list-safe copy. Native SDK objects are intentionally not sent
    /// across the Feature async boundary.
    public let userInfo: [String: String]
    /// Full APNs property-list payload, including nested `aps` and Feature data.
    public let propertyListData: Data

    public init(owner: MiniAppID, destination: String?, userInfo: [String: String], propertyListData: Data = Data()) {
        self.owner = owner
        self.destination = destination
        self.userInfo = userInfo
        self.propertyListData = propertyListData
    }

    public func propertyListUserInfo() throws -> [String: Any] {
        guard !propertyListData.isEmpty else { return userInfo }
        let value = try PropertyListSerialization.propertyList(from: propertyListData, options: [], format: nil)
        return value as? [String: Any] ?? [:]
    }
}

/// One app-level coordinator fans token changes out to explicit Feature/server
/// registrations while routing incoming payloads only to their declared owner.
@MainActor
public final class MiniAppRemotePushCoordinator {
    public static let shared = MiniAppRemotePushCoordinator()

    public typealias RegistrationHandler = @MainActor @Sendable (MiniAppRemotePushRegistrationEvent) async -> Void
    public typealias DeliveryHandler = @MainActor @Sendable (MiniAppRemotePushMessage) async -> MiniAppRemotePushFetchResult

    private struct Registration {
        let identity: MiniAppRemotePushIdentity
        let generation: UUID
        let registration: RegistrationHandler
        let delivery: DeliveryHandler
    }

    private var token: Data?
    private var registrationFailure: String?
    private var registrations: [MiniAppID: Registration] = [:]

    public init() {}

    public var appToken: Data? { token }
    public var registeredOwners: Set<MiniAppID> { Set(registrations.keys) }

    /// Called by UIApplicationDelegate after APNs returns the app device token.
    /// Repeated equal callbacks are idempotent; a changed token is sent to every
    /// currently connected owner using its own server identity and generation.
    public func didRegisterForRemoteNotifications(deviceToken: Data) async {
        guard token != deviceToken else { return }
        token = deviceToken
        registrationFailure = nil
        let snapshot = registrations
        for (owner, value) in snapshot where registrations[owner]?.generation == value.generation {
            await value.registration(.tokenChanged(token: deviceToken, identity: value.identity,
                                                     generation: value.generation))
        }
    }

    /// Registration failure is process/app state, not a Feature server failure.
    /// Each currently connected Feature receives the failure for its generation.
    public func didFailToRegisterForRemoteNotifications(_ error: Error) async {
        let message = String(describing: error)
        registrationFailure = message
        let snapshot = registrations
        for (owner, value) in snapshot where registrations[owner]?.generation == value.generation {
            await value.registration(.registrationFailed(message: message, generation: value.generation))
        }
    }

    fileprivate func connect(owner: MiniAppID, identity: MiniAppRemotePushIdentity,
                             registration: @escaping RegistrationHandler,
                             delivery: @escaping DeliveryHandler) async -> UUID {
        if let old = registrations.removeValue(forKey: owner), old.identity != identity {
            await old.registration(.ownerUnregistered(identity: old.identity))
        }
        let generation = UUID()
        registrations[owner] = Registration(identity: identity, generation: generation,
                                             registration: registration, delivery: delivery)
        if let token {
            await registration(.tokenChanged(token: token, identity: identity, generation: generation))
        } else if let registrationFailure {
            await registration(.registrationFailed(message: registrationFailure, generation: generation))
        }
        return generation
    }

    fileprivate func disconnect(owner: MiniAppID, generation: UUID) async {
        guard let value = registrations[owner], value.generation == generation else { return }
        registrations.removeValue(forKey: owner)
    }

    public func unregister(owner: MiniAppID) async {
        guard let value = registrations.removeValue(forKey: owner) else { return }
        await value.registration(.ownerUnregistered(identity: value.identity))
    }

    /// The existing notification route is the authority. Missing, malformed,
    /// disabled-by-disconnection, and unregistered owners are never broadcast.
    public func deliver(userInfo: [AnyHashable: Any]) async -> MiniAppRemotePushFetchResult {
        guard let route = MiniAppNotificationRoute.candidateRoute(userInfo: userInfo),
              let value = registrations[route.id]
        else { return .noData }
        let generation = value.generation
        let safe = userInfo.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            if let text = item.value as? String { result[key] = text }
            else if let number = item.value as? NSNumber { result[key] = number.stringValue }
        }
        let raw = (try? PropertyListSerialization.data(fromPropertyList: userInfo, format: .binary, options: 0)) ?? Data()
        let result = await value.delivery(.init(owner: route.id, destination: route.destination,
                                                userInfo: safe, propertyListData: raw))
        guard registrations[route.id]?.generation == generation else { return .noData }
        return result
    }
}

/// A Feature-scoped connection. Connect it to MiniAppRuntime so stop/restart
/// creates a new generation and late cleanup cannot remove the replacement.
@MainActor
public final class MiniAppRemotePushService {
    public let owner: MiniAppID
    public var identity: MiniAppRemotePushIdentity
    public var onRegistration: MiniAppRemotePushCoordinator.RegistrationHandler
    public var onDelivery: MiniAppRemotePushCoordinator.DeliveryHandler
    private let coordinator: MiniAppRemotePushCoordinator
    private var generation: UUID?

    public init(owner: MiniAppID, identity: MiniAppRemotePushIdentity,
                coordinator: MiniAppRemotePushCoordinator = .shared,
                onRegistration: @escaping MiniAppRemotePushCoordinator.RegistrationHandler = { _ in },
                onDelivery: @escaping MiniAppRemotePushCoordinator.DeliveryHandler = { _ in .noData }) {
        self.owner = owner
        self.identity = identity
        self.coordinator = coordinator
        self.onRegistration = onRegistration
        self.onDelivery = onDelivery
    }

    public func connect(to runtime: MiniAppRuntime) async throws {
        guard generation == nil else { return }
        let created = await coordinator.connect(owner: owner, identity: identity,
                                                registration: onRegistration, delivery: onDelivery)
        generation = created
        try runtime.onShutdownAsync { [weak self, coordinator, owner] in
            await coordinator.disconnect(owner: owner, generation: created)
            if self?.generation == created { self?.generation = nil }
        }
    }

    public func unregister() async {
        generation = nil
        await coordinator.unregister(owner: owner)
    }
}

/// Thread-safe UIApplicationDelegate completion fan-in. Call finishAdding after
/// creating tickets. Completion fires exactly once, including the zero-ticket case.
public final class MiniAppRemotePushCompletionAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var addingFinished = false
    private var completed = false
    private var result: MiniAppRemotePushFetchResult = .noData
    private let completion: @Sendable (MiniAppRemotePushFetchResult) -> Void

    public init(completion: @escaping @Sendable (MiniAppRemotePushFetchResult) -> Void) {
        self.completion = completion
    }

    public func ticket() -> @Sendable (MiniAppRemotePushFetchResult) -> Void {
        lock.lock()
        precondition(!addingFinished, "Tickets must be created before finishAdding().")
        pending += 1
        lock.unlock()
        let once = MiniAppRemotePushOnce()
        return { [weak self] value in
            guard once.claim() else { return }
            self?.leave(value)
        }
    }

    public func finishAdding() {
        lock.lock(); addingFinished = true
        let output = completionIfReadyLocked()
        lock.unlock()
        if let output { completion(output) }
    }

    private func leave(_ value: MiniAppRemotePushFetchResult) {
        lock.lock()
        if value.rawValue > result.rawValue { result = value }
        pending -= 1
        let output = completionIfReadyLocked()
        lock.unlock()
        if let output { completion(output) }
    }

    private func completionIfReadyLocked() -> MiniAppRemotePushFetchResult? {
        guard addingFinished, pending == 0, !completed else { return nil }
        completed = true
        return result
    }
}

private final class MiniAppRemotePushOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; guard !used else { return false }; used = true; return true }
}
