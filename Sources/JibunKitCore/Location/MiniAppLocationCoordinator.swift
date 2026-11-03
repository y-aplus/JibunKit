import Foundation
#if os(iOS)
import CoreLocation
#endif

@MainActor
public protocol MiniAppLocationNativeClient: AnyObject {
    var authorization: MiniAppLocationAuthorization { get }
    var monitoredRegionIDs: Set<String> { get }
    func isMonitoringAvailable(for kind: MiniAppLocationMonitoringKind) -> Bool
    var maximumRegionMonitoringDistance: Double { get }
    var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)? { get set }
    #if os(iOS)
    var coreLocationHandler: (@MainActor (UUID, [CLLocation]) -> Void)? { get set }
    #endif
    func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest)
    func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID)
    func stopUpdates(generation: UUID)
    func startMonitoring(_ registration: MiniAppLocationRegistration)
    func stopMonitoring(identifier: String)
    func requestState(identifier: String)
    /// One location fix, delivered as `.locations` or `.failed` with `generation`.
    func requestLocation(desiredAccuracy: Double, generation: UUID)
    func cancelLocationRequest(generation: UUID)
    func isAvailable(_ monitor: MiniAppLocationSystemMonitor) -> Bool
    func setMonitoring(_ monitor: MiniAppLocationSystemMonitor, active: Bool)
}

/// Clients written before one-time fixes and system monitors report them unavailable.
extension MiniAppLocationNativeClient {
    public func requestLocation(desiredAccuracy: Double, generation: UUID) {
        eventHandler?(.failed(generation: generation, message: "One-time location requests are unavailable"))
    }
    public func cancelLocationRequest(generation: UUID) {}
    public func isAvailable(_ monitor: MiniAppLocationSystemMonitor) -> Bool { false }
    public func setMonitoring(_ monitor: MiniAppLocationSystemMonitor, active: Bool) {}
}

public enum MiniAppLocationNativeEvent: Sendable, Equatable {
    case locations(generation: UUID, [MiniAppLocationSample])
    case authorizationChanged(MiniAppLocationAuthorization)
    case entered(identifier: String)
    case exited(identifier: String)
    case state(identifier: String, MiniAppLocationRegionState)
    case monitoringFailed(identifier: String?, message: String)
    case failed(generation: UUID?, message: String)
    case significantChange([MiniAppLocationSample])
    case visit(MiniAppLocationVisit)
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

public protocol MiniAppLocationMonitorStore: Sendable {
    func read() throws -> [MiniAppLocationMonitorRegistration]
    func write(_ monitors: [MiniAppLocationMonitorRegistration]) throws
}

public struct MiniAppUserDefaultsLocationMonitorStore: MiniAppLocationMonitorStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "jibunkit.location.monitors") {
        self.defaults = defaults; self.key = key
    }
    public func read() throws -> [MiniAppLocationMonitorRegistration] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([MiniAppLocationMonitorRegistration].self, from: data)
    }
    public func write(_ monitors: [MiniAppLocationMonitorRegistration]) throws {
        defaults.set(try JSONEncoder().encode(monitors), forKey: key)
    }
}

public final class MiniAppLocationAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    private var suspended = false
    public init() {}
    public func setAllowed(_ allowed: Bool) { lock.lock(); value = allowed; lock.unlock() }
    public func isAllowed() -> Bool { lock.lock(); defer { lock.unlock() }; return value == true && !suspended }
    public func isClosed() -> Bool { lock.lock(); defer { lock.unlock() }; return value == false || suspended }
    public func setSuspended(_ suspended: Bool) { lock.lock(); self.suspended = suspended; lock.unlock() }
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
    private let monitorStore: any MiniAppLocationMonitorStore
    private var registrations: [String: MiniAppLocationRegistration] = [:]
    private var monitors: Set<MiniAppLocationMonitorRegistration> = []
    /// The system monitors this process has started.
    private var activeMonitors: Set<MiniAppLocationSystemMonitor> = []
    private var monitorReceivers: [MiniAppID: @MainActor @Sendable (MiniAppLocationMonitorEvent) -> Void] = [:]
    /// One-time requests that have not answered yet.
    private var requestOwners: [UUID: MiniAppID] = [:]
    private struct Consumer {
        let token: UUID
        let receive: @MainActor @Sendable (MiniAppLocationEvent) -> Void
        #if os(iOS)
        var receiveCoreLocations: (@MainActor ([CLLocation], UUID) -> Void)?
        #endif
    }
    private var consumers: [MiniAppID: Consumer] = [:]
    private var coldConsumers: [MiniAppID: @MainActor @Sendable (MiniAppLocationEvent) -> Void] = [:]
    private var admissions: [MiniAppID: MiniAppLocationAdmission] = [:]
    private var updateOwners: [MiniAppID: UUID] = [:]
    public private(set) var persistenceFailure: String?

    public init(native: (any MiniAppLocationNativeClient)? = nil,
                store: any MiniAppLocationRegistrationStore = MiniAppUserDefaultsLocationStore(),
                monitorStore: any MiniAppLocationMonitorStore = MiniAppUserDefaultsLocationMonitorStore()) {
        self.native = native ?? MiniAppCoreLocationClient()
        self.store = store
        self.monitorStore = monitorStore
        do {
            monitors = Set(try monitorStore.read())
            let restored = try store.read()
            var localKeys: Set<String> = []
            for registration in restored where registration.owner.isValid && !registration.localID.isEmpty {
                let key = registration.owner.rawValue + "\u{0}" + registration.localID
                guard localKeys.insert(key).inserted else {
                    throw MiniAppLocationFailure.persistenceUnavailable("duplicate owner/localID")
                }
                registrations[registration.id] = registration
            }
        } catch {
            persistenceFailure = error.localizedDescription
        }
        self.native.eventHandler = { [weak self] event in self?.receive(event) }
        #if os(iOS)
        self.native.coreLocationHandler = { [weak self] generation, locations in
            guard let self, let owner = self.updateOwners.first(where: { $0.value == generation })?.key
                    ?? self.requestOwners[generation] else { return }
            self.consumers[owner]?.receiveCoreLocations?(locations, generation)
        }
        #endif
    }

    public var authorization: MiniAppLocationAuthorization { native.authorization }
    public var allRegistrations: [MiniAppLocationRegistration] { Array(registrations.values) }

    public func prepare(owner: MiniAppID, admission: MiniAppLocationAdmission,
                        receiveCold: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) {
        admissions[owner] = admission
        coldConsumers[owner] = receiveCold
    }

    /// Receives the owner's system monitor events, also before a view connects
    /// while management allows the owner.
    public func prepareMonitorDelivery(owner: MiniAppID,
                                       receive: @escaping @MainActor @Sendable (MiniAppLocationMonitorEvent) -> Void) {
        monitorReceivers[owner] = receive
    }

    public func connect(owner: MiniAppID, token: UUID,
                        receive: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) {
        if consumers[owner]?.token != token {
            if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
            cancelRequests(owner: owner)
        }
        consumers[owner] = Consumer(token: token, receive: receive)
        if let persistenceFailure { receive(.failed(generation: nil, persistenceFailure)) }
    }

    public func isConnected(owner: MiniAppID, token: UUID) -> Bool { consumers[owner]?.token == token }

    #if os(iOS)
    public func setCoreLocationReceiver(owner: MiniAppID, token: UUID,
                                       receive: @escaping @MainActor ([CLLocation], UUID) -> Void) {
        guard isConnected(owner: owner, token: token) else { return }
        consumers[owner]?.receiveCoreLocations = receive
    }
    #endif

    @discardableResult
    public func connect(owner: MiniAppID,
                        receive: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) -> UUID {
        let token = UUID(); connect(owner: owner, token: token, receive: receive); return token
    }

    public func disconnect(owner: MiniAppID, token: UUID) {
        guard consumers[owner]?.token == token else { return }
        consumers.removeValue(forKey: owner)
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
        cancelRequests(owner: owner)
    }

    private func cancelRequests(owner: MiniAppID) {
        for (generation, requester) in requestOwners where requester == owner {
            requestOwners.removeValue(forKey: generation)
            native.cancelLocationRequest(generation: generation)
        }
    }

    /// Apply a Feature-consent revocation without changing app-wide OS permission.
    /// Durable registrations are owned work, so revocation removes this owner only.
    public func revoke(owner: MiniAppID) throws {
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
        cancelRequests(owner: owner)
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

    /// Asks for one fix, answered once as `.locations` or `.failed` with the
    /// returned generation. Unlike updates, an owner may have several pending.
    @discardableResult
    public func requestLocation(owner: MiniAppID, featureConsent: Bool, desiredAccuracy: Double) throws -> UUID {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        let generation = UUID()
        requestOwners[generation] = owner
        native.requestLocation(desiredAccuracy: desiredAccuracy, generation: generation)
        return generation
    }

    public func cancelLocationRequest(owner: MiniAppID, generation: UUID) throws {
        guard requestOwners[generation] == owner else { throw MiniAppLocationFailure.staleGeneration }
        requestOwners.removeValue(forKey: generation)
        native.cancelLocationRequest(generation: generation)
    }

    /// Keeps `monitor` running for the owner until it stops it, across app
    /// launches: like regions, the choice is persisted and reconnected by
    /// `reconnectPersistedMonitoring(owner:)`.
    public func startMonitoring(_ monitor: MiniAppLocationSystemMonitor, owner: MiniAppID, featureConsent: Bool) throws {
        try requireWritableStore()
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        guard native.isAvailable(monitor) else { throw MiniAppLocationFailure.monitoringUnavailable }
        let entry = MiniAppLocationMonitorRegistration(owner: owner, monitor: monitor)
        if monitors.insert(entry).inserted {
            do { try persistMonitors() } catch { monitors.remove(entry); throw error }
        }
        activate(monitor)
    }

    /// Stops `monitor` for the owner; the service stops once no owner in this build uses it.
    public func stopMonitoring(_ monitor: MiniAppLocationSystemMonitor, owner: MiniAppID) throws {
        try requireWritableStore()
        let entry = MiniAppLocationMonitorRegistration(owner: owner, monitor: monitor)
        guard monitors.remove(entry) != nil else { return }
        do { try persistMonitors() } catch { monitors.insert(entry); throw error }
        deactivateIfUnused(monitor)
    }

    public func systemMonitors(owner: MiniAppID) -> Set<MiniAppLocationSystemMonitor> {
        Set(monitors.filter { $0.owner == owner }.map(\.monitor))
    }

    private func activate(_ monitor: MiniAppLocationSystemMonitor) {
        guard activeMonitors.insert(monitor).inserted else { return }
        native.setMonitoring(monitor, active: true)
    }

    /// Owners missing from this build, whose services were never created,
    /// do not keep a monitor running.
    private func deactivateIfUnused(_ monitor: MiniAppLocationSystemMonitor) {
        guard activeMonitors.contains(monitor),
              !monitors.contains(where: { $0.monitor == monitor && admissions[$0.owner] != nil }) else { return }
        activeMonitors.remove(monitor)
        native.setMonitoring(monitor, active: false)
    }

    @discardableResult
    public func register(owner: MiniAppID, localID: String, region: MiniAppLocationRegion,
                         featureConsent: Bool) throws -> MiniAppLocationRegistration {
        try requireWritableStore()
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        let kind: MiniAppLocationMonitoringKind
        switch region { case .geofence: kind = .geofence; case .beacon: kind = .beacon }
        guard native.isMonitoringAvailable(for: kind) else { throw MiniAppLocationFailure.monitoringUnavailable }
        if case .geofence(_, _, let radius, _, _) = region,
           native.maximumRegionMonitoringDistance > 0, radius > native.maximumRegionMonitoringDistance {
            throw MiniAppLocationFailure.radiusExceedsMaximum(
                requested: radius, maximum: native.maximumRegionMonitoringDistance)
        }
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
        try requireWritableStore()
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        if let generation, registration.generation != generation { throw MiniAppLocationFailure.staleGeneration }
        registrations.removeValue(forKey: registration.id)
        do { try persist() }
        catch { registrations[registration.id] = registration; throw error }
        native.stopMonitoring(identifier: registration.id)
    }

    /// Removes the owner's regions and system monitors.
    public func unregisterAll(owner: MiniAppID) throws {
        try requireWritableStore()
        let owned = registrations.values.filter { $0.owner == owner }
        let ownedMonitors = monitors.filter { $0.owner == owner }
        for registration in owned { registrations.removeValue(forKey: registration.id) }
        monitors.subtract(ownedMonitors)
        do {
            try persist()
            if !ownedMonitors.isEmpty { try persistMonitors() }
        } catch {
            for registration in owned { registrations[registration.id] = registration }
            monitors.formUnion(ownedMonitors)
            try? persist()
            throw error
        }
        for registration in owned { native.stopMonitoring(identifier: registration.id) }
        for monitor in Set(ownedMonitors.map(\.monitor)) { deactivateIfUnused(monitor) }
    }

    public func requestState(owner: MiniAppID, localID: String) throws {
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        native.requestState(identifier: registration.id)
    }

    /// Reconnects persisted ownership to the manager during app launch. This does
    /// not invent registrations or restart continuous updates.
    public func registrations(owner: MiniAppID) -> [MiniAppLocationRegistration] {
        registrations.values.filter { $0.owner == owner }.sorted { $0.localID < $1.localID }
    }

    public func reconnectPersistedMonitoring(owner: MiniAppID) throws {
        try requireWritableStore()
        guard admissions[owner]?.isAllowed() == true else { return }
        guard native.authorization == .whenInUse || native.authorization == .always else { return }
        var occupied = native.monitoredRegionIDs
        for registration in registrations.values where registration.owner == owner && !occupied.contains(registration.id) {
            guard occupied.count < Self.regionLimit else {
                deliver(to: owner, .monitoringFailed(registration, "Core Location region limit \(Self.regionLimit) reached"))
                continue
            }
            native.startMonitoring(registration)
            occupied.insert(registration.id)
        }
        // Core Location delivers the events that relaunched the app only to a
        // manager that has started the service again during launch.
        for entry in monitors where entry.owner == owner && native.isAvailable(entry.monitor) {
            activate(entry.monitor)
        }
    }

    private func requireWritableStore() throws {
        if let persistenceFailure { throw MiniAppLocationFailure.persistenceUnavailable(persistenceFailure) }
    }
    private func persist() throws { try requireWritableStore(); try store.write(Array(registrations.values)) }
    private func persistMonitors() throws {
        try requireWritableStore()
        try monitorStore.write(monitors.sorted { ($0.owner.rawValue, $0.monitor.rawValue) < ($1.owner.rawValue, $1.monitor.rawValue) })
    }

    private func deliver(to owner: MiniAppID, _ event: MiniAppLocationEvent) {
        if let consumer = consumers[owner] { consumer.receive(event) }
        else if admissions[owner]?.isAllowed() == true { coldConsumers[owner]?(event) }
    }

    private func receive(_ event: MiniAppLocationNativeEvent) {
        switch event {
        case .locations(let generation, let samples):
            guard let owner = updateOwners.first(where: { $0.value == generation })?.key
                    ?? requestOwners.removeValue(forKey: generation) else { return }
            deliver(to: owner, .locations(generation: generation, samples: samples))
        case .authorizationChanged(let status):
            if status != .whenInUse && status != .always {
                for generation in updateOwners.values { native.stopUpdates(generation: generation) }
                updateOwners.removeAll()
                for generation in requestOwners.keys { native.cancelLocationRequest(generation: generation) }
                requestOwners.removeAll()
            }
            for owner in Set(consumers.keys).union(coldConsumers.keys) { deliver(to: owner, .authorizationChanged(status)) }
        case .entered(let id): deliver(id) { .entered($0) }
        case .exited(let id): deliver(id) { .exited($0) }
        case .state(let id, let state): deliver(id) { .state($0, state) }
        case .monitoringFailed(let id, let message):
            if let id, let registration = registrations[id] {
                registrations.removeValue(forKey: id)
                do {
                    try persist()
                    deliver(to: registration.owner, .monitoringFailed(registration, message))
                } catch {
                    registrations[id] = registration
                    deliver(to: registration.owner, .monitoringFailed(
                        registration, "\(message); registration metadata cleanup failed: \(error.localizedDescription)"))
                }
            } else if id == nil {
                for owner in Set(consumers.keys).union(coldConsumers.keys) {
                    deliver(to: owner, .monitoringFailed(nil, message))
                }
            }
        case .failed(let generation, let message):
            if let generation, let owner = updateOwners.first(where: { $0.value == generation })?.key
                ?? requestOwners.removeValue(forKey: generation) {
                deliver(to: owner, .failed(generation: generation, message))
            }
        case .significantChange(let samples): deliver(.significantChanges, .significantChange(samples))
        case .visit(let visit): deliver(.visits, .visit(visit))
        }
    }

    private func deliver(_ monitor: MiniAppLocationSystemMonitor, _ event: MiniAppLocationMonitorEvent) {
        for owner in Set(monitors.filter { $0.monitor == monitor }.map(\.owner))
        where consumers[owner] != nil || admissions[owner]?.isAllowed() == true {
            monitorReceivers[owner]?(event)
        }
    }

    private func deliver(_ identifier: String,
                         event: (MiniAppLocationRegistration) -> MiniAppLocationEvent) {
        guard let registration = registrations[identifier] else { return }
        deliver(to: registration.owner, event(registration))
    }
}

@MainActor
public final class MiniAppLocationService {
    public let owner: MiniAppID
    private let coordinator: MiniAppLocationCoordinator
    private let featureConsent: @MainActor @Sendable () -> Bool
    private let admission = MiniAppLocationAdmission()
    private var activeToken: UUID?
    private weak var connectedRuntime: MiniAppRuntime?
    public var receive: (@MainActor @Sendable (MiniAppLocationEvent) -> Void)?
    #if os(iOS)
    public var receiveCoreLocations: (@MainActor ([CLLocation], UUID) -> Void)?
    #endif
    /// Significant location changes and visits, including those that relaunched the app.
    public var receiveMonitorEvent: (@MainActor @Sendable (MiniAppLocationMonitorEvent) -> Void)?

    public init(owner: MiniAppID, coordinator: MiniAppLocationCoordinator = .shared,
                featureConsent: @escaping @MainActor @Sendable () -> Bool) {
        precondition(owner.isValid)
        self.owner = owner; self.coordinator = coordinator; self.featureConsent = featureConsent
        coordinator.prepare(owner: owner, admission: admission) { [weak self] event in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receive?(event)
        }
        coordinator.prepareMonitorDelivery(owner: owner) { [weak self] event in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receiveMonitorEvent?(event)
        }
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        let token = UUID()
        let coordinator = coordinator, owner = owner
        try runtime.onShutdownAsync { [weak self] in
            coordinator.disconnect(owner: owner, token: token)
            if self?.activeToken == token {
                self?.activeToken = nil
                self?.connectedRuntime = nil
            }
        }
        coordinator.connect(owner: owner, token: token) { [weak self] event in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receive?(event)
        }
        #if os(iOS)
        coordinator.setCoreLocationReceiver(owner: owner, token: token) { [weak self] locations, generation in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receiveCoreLocations?(locations, generation)
        }
        #endif
        activeToken = token
        connectedRuntime = runtime
    }

    private func requireConnection() throws {
        guard let activeToken, connectedRuntime?.isClosed == false, !admission.isClosed(),
              coordinator.isConnected(owner: owner, token: activeToken) else {
            throw MiniAppLocationFailure.stopped
        }
    }

    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) throws {
        try requireConnection()
        try coordinator.requestAuthorization(owner: owner, featureConsent: featureConsent(), request: request)
    }
    public func startUpdates(_ configuration: MiniAppLocationUpdateConfiguration) throws -> UUID {
        try requireConnection()
        return try coordinator.startUpdates(owner: owner, featureConsent: featureConsent(), configuration: configuration)
    }
    public func stopUpdates(generation: UUID) throws { try requireConnection(); try coordinator.stopUpdates(owner: owner, generation: generation) }
    /// One fix, delivered to `receive` as `.locations` or `.failed` with the returned generation.
    public func requestLocation(desiredAccuracy: Double) throws -> UUID {
        try requireConnection()
        return try coordinator.requestLocation(owner: owner, featureConsent: featureConsent(), desiredAccuracy: desiredAccuracy)
    }
    public func cancelLocationRequest(generation: UUID) throws {
        try requireConnection(); try coordinator.cancelLocationRequest(owner: owner, generation: generation)
    }
    public func startMonitoring(_ monitor: MiniAppLocationSystemMonitor) throws {
        try requireConnection()
        try coordinator.startMonitoring(monitor, owner: owner, featureConsent: featureConsent())
    }
    public func stopMonitoring(_ monitor: MiniAppLocationSystemMonitor) throws {
        try requireConnection(); try coordinator.stopMonitoring(monitor, owner: owner)
    }
    public var systemMonitors: Set<MiniAppLocationSystemMonitor> { coordinator.systemMonitors(owner: owner) }
    public func register(localID: String, region: MiniAppLocationRegion) throws -> MiniAppLocationRegistration {
        try requireConnection()
        return try coordinator.register(owner: owner, localID: localID, region: region, featureConsent: featureConsent())
    }
    public func unregister(localID: String, generation: UUID? = nil) throws {
        try requireConnection()
        try coordinator.unregister(owner: owner, localID: localID, generation: generation)
    }
    public func unregisterAll() throws { try requireConnection(); try coordinator.unregisterAll(owner: owner) }
    public func unregisterAllOwned() throws { try coordinator.unregisterAll(owner: owner) }
    public func requestState(localID: String) throws { try requireConnection(); try coordinator.requestState(owner: owner, localID: localID) }
    public var registrations: [MiniAppLocationRegistration] { coordinator.registrations(owner: owner) }
    public func reconnectPersistedMonitoring() throws {
        guard featureConsent() else { try coordinator.revoke(owner: owner); return }
        try coordinator.reconnectPersistedMonitoring(owner: owner)
    }
    public func featureConsentDidChange() throws {
        if !featureConsent() { try coordinator.revoke(owner: owner) }
    }

    public var externalAccess: MiniAppExternalAccess {
        let owner = owner, admission = admission, coordinator = coordinator
        return MiniAppExternalAccess(id: owner, prepare: { admission.setAllowed($0) }, close: {
            admission.setAllowed(false)
            try await MainActor.run { try coordinator.revoke(owner: owner) }
        }, open: {
            admission.setAllowed(true)
        }, restoreLifecycle: { inner in
            MiniAppRestoreLifecycle(stop: {
                admission.setSuspended(true)
                try await inner?.stop()
            }, resume: {
                try await inner?.resume()
                admission.setSuspended(false)
            })
        })
    }
}
