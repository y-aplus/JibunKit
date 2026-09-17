import Foundation

@MainActor
public protocol MiniAppLocationNativeClient: AnyObject {
    var authorization: MiniAppLocationAuthorization { get }
    var monitoredRegionIDs: Set<String> { get }
    var isRegionMonitoringAvailable: Bool { get }
    var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)? { get set }
    func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest)
    func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID)
    func stopUpdates(generation: UUID)
    func startMonitoring(_ registration: MiniAppLocationRegistration)
    func stopMonitoring(identifier: String)
    func requestState(identifier: String)
}

public enum MiniAppLocationNativeEvent: Sendable, Equatable {
    case locations(generation: UUID, [MiniAppLocationSample])
    case authorizationChanged(MiniAppLocationAuthorization)
    case entered(identifier: String)
    case exited(identifier: String)
    case state(identifier: String, MiniAppLocationRegionState)
    case monitoringFailed(identifier: String?, message: String)
    case failed(generation: UUID?, message: String)
}

public protocol MiniAppLocationRegistrationStore: Sendable {
    func read() throws -> [MiniAppLocationRegistration]
    func write(_ registrations: [MiniAppLocationRegistration]) throws
}

public struct MiniAppUserDefaultsLocationStore: MiniAppLocationRegistrationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "jibunkit.location.registrations") {
        self.defaults = defaults; self.key = key
    }
    public func read() throws -> [MiniAppLocationRegistration] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([MiniAppLocationRegistration].self, from: data)
    }
    public func write(_ registrations: [MiniAppLocationRegistration]) throws {
        defaults.set(try JSONEncoder().encode(registrations), forKey: key)
    }
}

/// App-wide reservation and delivery boundary for Core Location's shared region pool.
/// A Feature can only remove its own identifiers; unknown/native registrations count
/// toward the system limit and are never stopped by JibunKit.
@MainActor
public final class MiniAppLocationCoordinator {
    public static let regionLimit = 20
    public static let shared = MiniAppLocationCoordinator()

    private let native: any MiniAppLocationNativeClient
    private let store: any MiniAppLocationRegistrationStore
    private var registrations: [String: MiniAppLocationRegistration] = [:]
    private var consumers: [MiniAppID: @MainActor @Sendable (MiniAppLocationEvent) -> Void] = [:]
    private var updateOwners: [MiniAppID: UUID] = [:]

    public init(native: (any MiniAppLocationNativeClient)? = nil,
                store: any MiniAppLocationRegistrationStore = MiniAppUserDefaultsLocationStore()) {
        self.native = native ?? MiniAppCoreLocationClient()
        self.store = store
        if let restored = try? store.read() {
            for registration in restored where registration.owner.isValid && !registration.localID.isEmpty {
                registrations[registration.id] = registration
            }
        }
        self.native.eventHandler = { [weak self] event in self?.receive(event) }
    }

    public var authorization: MiniAppLocationAuthorization { native.authorization }
    public var allRegistrations: [MiniAppLocationRegistration] { Array(registrations.values) }

    public func connect(owner: MiniAppID,
                        receive: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) {
        consumers[owner] = receive
    }

    public func disconnect(owner: MiniAppID) {
        consumers.removeValue(forKey: owner)
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
    }

    /// Apply a Feature-consent revocation without changing app-wide OS permission.
    /// Durable registrations are owned work, so revocation removes this owner only.
    public func revoke(owner: MiniAppID) throws {
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
        try unregisterAll(owner: owner)
    }

    public func requestAuthorization(owner: MiniAppID, featureConsent: Bool,
                                     request: MiniAppLocationAuthorizationRequest) throws {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        native.requestAuthorization(request)
    }

    @discardableResult
    public func startUpdates(owner: MiniAppID, featureConsent: Bool,
                             configuration: MiniAppLocationUpdateConfiguration) throws -> UUID {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        if let previous = updateOwners[owner] { native.stopUpdates(generation: previous) }
        let generation = UUID()
        updateOwners[owner] = generation
        native.startUpdates(configuration: configuration, generation: generation)
        return generation
    }

    public func stopUpdates(owner: MiniAppID, generation: UUID) throws {
        guard updateOwners[owner] == generation else { throw MiniAppLocationFailure.staleGeneration }
        updateOwners.removeValue(forKey: owner)
        native.stopUpdates(generation: generation)
    }

    @discardableResult
    public func register(owner: MiniAppID, localID: String, region: MiniAppLocationRegion,
                         featureConsent: Bool) throws -> MiniAppLocationRegistration {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        guard native.isRegionMonitoringAvailable else { throw MiniAppLocationFailure.monitoringUnavailable }
        guard !registrations.values.contains(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.duplicateLocalID
        }
        let occupied = native.monitoredRegionIDs.union(registrations.keys).count
        guard occupied < Self.regionLimit else {
            throw MiniAppLocationFailure.capacityExceeded(limit: Self.regionLimit, occupied: occupied)
        }
        let registration = try MiniAppLocationRegistration(owner: owner, localID: localID, region: region)
        registrations[registration.id] = registration
        do {
            try persist()
            native.startMonitoring(registration)
            return registration
        } catch {
            registrations.removeValue(forKey: registration.id)
            try? persist()
            throw error
        }
    }

    public func unregister(owner: MiniAppID, localID: String, generation: UUID? = nil) throws {
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        if let generation, registration.generation != generation { throw MiniAppLocationFailure.staleGeneration }
        registrations.removeValue(forKey: registration.id)
        do { try persist() }
        catch { registrations[registration.id] = registration; throw error }
        native.stopMonitoring(identifier: registration.id)
    }

    public func unregisterAll(owner: MiniAppID) throws {
        let owned = registrations.values.filter { $0.owner == owner }
        for registration in owned { registrations.removeValue(forKey: registration.id) }
        do { try persist() }
        catch {
            for registration in owned { registrations[registration.id] = registration }
            throw error
        }
        for registration in owned { native.stopMonitoring(identifier: registration.id) }
    }

    public func requestState(owner: MiniAppID, localID: String) throws {
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        native.requestState(identifier: registration.id)
    }

    /// Reconnects persisted ownership to the manager during app launch. This does
    /// not invent registrations or restart continuous updates.
    public func reconnectPersistedMonitoring() {
        guard native.authorization == .whenInUse || native.authorization == .always else { return }
        let monitored = native.monitoredRegionIDs
        for registration in registrations.values where !monitored.contains(registration.id) {
            native.startMonitoring(registration)
        }
    }

    private func persist() throws { try store.write(Array(registrations.values)) }

    private func receive(_ event: MiniAppLocationNativeEvent) {
        switch event {
        case .locations(let generation, let samples):
            guard let owner = updateOwners.first(where: { $0.value == generation })?.key else { return }
            consumers[owner]?(.locations(generation: generation, samples: samples))
        case .authorizationChanged(let status):
            if status != .whenInUse && status != .always {
                for generation in updateOwners.values { native.stopUpdates(generation: generation) }
                updateOwners.removeAll()
            }
            for consumer in consumers.values { consumer(.authorizationChanged(status)) }
        case .entered(let id): deliver(id) { .entered($0) }
        case .exited(let id): deliver(id) { .exited($0) }
        case .state(let id, let state): deliver(id) { .state($0, state) }
        case .monitoringFailed(let id, let message):
            if let id, let registration = registrations[id] {
                registrations.removeValue(forKey: id)
                do {
                    try persist()
                    consumers[registration.owner]?(.monitoringFailed(registration, message))
                } catch {
                    registrations[id] = registration
                    consumers[registration.owner]?(.monitoringFailed(
                        registration, "\(message); registration metadata cleanup failed: \(error.localizedDescription)"))
                }
            } else {
                for consumer in consumers.values { consumer(.monitoringFailed(nil, message)) }
            }
        case .failed(let generation, let message):
            if let generation, let owner = updateOwners.first(where: { $0.value == generation })?.key {
                consumers[owner]?(.failed(generation: generation, message))
            }
        }
    }

    private func deliver(_ identifier: String,
                         event: (MiniAppLocationRegistration) -> MiniAppLocationEvent) {
        guard let registration = registrations[identifier] else { return }
        consumers[registration.owner]?(event(registration))
    }
}

@MainActor
public final class MiniAppLocationService {
    public let owner: MiniAppID
    private let coordinator: MiniAppLocationCoordinator
    private let featureConsent: @MainActor @Sendable () -> Bool
    public var receive: (@MainActor @Sendable (MiniAppLocationEvent) -> Void)?

    public init(owner: MiniAppID, coordinator: MiniAppLocationCoordinator = .shared,
                featureConsent: @escaping @MainActor @Sendable () -> Bool) {
        precondition(owner.isValid)
        self.owner = owner; self.coordinator = coordinator; self.featureConsent = featureConsent
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        coordinator.connect(owner: owner) { [weak self] in self?.receive?($0) }
        try runtime.onShutdownAsync { [weak self] in
            guard let self else { return }
            self.coordinator.disconnect(owner: self.owner)
        }
    }

    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) throws {
        try coordinator.requestAuthorization(owner: owner, featureConsent: featureConsent(), request: request)
    }
    public func startUpdates(_ configuration: MiniAppLocationUpdateConfiguration) throws -> UUID {
        try coordinator.startUpdates(owner: owner, featureConsent: featureConsent(), configuration: configuration)
    }
    public func stopUpdates(generation: UUID) throws { try coordinator.stopUpdates(owner: owner, generation: generation) }
    public func register(localID: String, region: MiniAppLocationRegion) throws -> MiniAppLocationRegistration {
        try coordinator.register(owner: owner, localID: localID, region: region, featureConsent: featureConsent())
    }
    public func unregister(localID: String, generation: UUID? = nil) throws {
        try coordinator.unregister(owner: owner, localID: localID, generation: generation)
    }
    public func unregisterAll() throws { try coordinator.unregisterAll(owner: owner) }
    public func requestState(localID: String) throws { try coordinator.requestState(owner: owner, localID: localID) }
    public func featureConsentDidChange() throws {
        if !featureConsent() { try coordinator.revoke(owner: owner) }
    }
}
