import Foundation

public enum MiniAppBluetoothAuthorization: String, Sendable, Equatable {
    case notDetermined, restricted, denied, allowed, unsupported
}

public enum MiniAppBluetoothPower: String, Sendable, Equatable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public struct MiniAppBluetoothPeripheral: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String?
    public let rssi: Int?
    public let advertisement: [String: String]

    public init(id: UUID, name: String? = nil, rssi: Int? = nil,
                advertisement: [String: String] = [:]) {
        self.id = id; self.name = name; self.rssi = rssi; self.advertisement = advertisement
    }
}

public struct MiniAppBluetoothCharacteristic: Sendable, Equatable, Hashable {
    public let service: String
    public let characteristic: String
    public init(service: String, characteristic: String) {
        self.service = service; self.characteristic = characteristic
    }
}

public enum MiniAppBluetoothWriteType: Sendable { case withResponse, withoutResponse }

public enum MiniAppBluetoothEvent: Sendable, Equatable {
    case powerChanged(MiniAppBluetoothPower, authorization: MiniAppBluetoothAuthorization)
    case discovered(MiniAppBluetoothPeripheral)
    case connected(peripheral: UUID, generation: UUID, restored: Bool)
    case disconnected(peripheral: UUID, generation: UUID, message: String?)
    case services(peripheral: UUID, generation: UUID, identifiers: [String])
    case characteristics(peripheral: UUID, generation: UUID, service: String, identifiers: [String])
    case value(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic, data: Data, notifying: Bool)
    case notificationChanged(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic, enabled: Bool)
    case writeCompleted(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic)
    case failed(peripheral: UUID?, generation: UUID?, message: String)
}

public enum MiniAppBluetoothFailure: Error, Sendable, Equatable {
    case stopped
    case wrongOwner
    case staleGeneration
    case bluetoothUnavailable(MiniAppBluetoothPower)
    case permissionDenied(MiniAppBluetoothAuthorization)
    case unknownPeripheral
    case unknownCharacteristic
}

public struct MiniAppBluetoothConnection: Sendable, Equatable {
    public let owner: MiniAppID
    public let peripheral: UUID
    public let generation: UUID
}

@MainActor
public protocol MiniAppBluetoothNativeCentral: AnyObject {
    var power: MiniAppBluetoothPower { get }
    var authorization: MiniAppBluetoothAuthorization { get }
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)? { get set }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool)
    func stopScan()
    func connect(peripheral: UUID, generation: UUID)
    func disconnect(peripheral: UUID, generation: UUID)
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID)
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String,
                                 peripheral: UUID, generation: UUID)
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID)
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic,
               type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID)
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic,
                   peripheral: UUID, generation: UUID)
    func stopAll()
}

/// App-wide owner router. Native managers and their restoration identifiers are
/// deliberately per owner; one Feature can never cancel another Feature's scan
/// or connection, even when both managers refer to the same physical peripheral.
@MainActor
public final class MiniAppBluetoothCoordinator {
    public typealias NativeFactory = @MainActor (MiniAppID, String) -> any MiniAppBluetoothNativeCentral

    private struct Consumer {
        let token: UUID
        let receive: @MainActor @Sendable (MiniAppBluetoothEvent) -> Void
    }
    private struct OwnerState {
        let native: any MiniAppBluetoothNativeCentral
        var consumer: Consumer?
        var connections: [UUID: UUID] = [:]
        var admitted = false
    }

    public static let shared = MiniAppBluetoothCoordinator()
    private let factory: NativeFactory
    private var owners: [MiniAppID: OwnerState] = [:]

    public init(factory: @escaping NativeFactory = { owner, identifier in
        MiniAppCoreBluetoothCentral(owner: owner, restorationIdentifier: identifier)
    }) { self.factory = factory }

    public static func restorationIdentifier(for owner: MiniAppID) -> String {
        "dev.jibunkit.bluetooth.central.\(owner.storageNamespace)"
    }

    /// Called synchronously by the host launch hook. A disabled owner must not
    /// call this method, otherwise constructing CBCentralManager can revive it.
    public func prepareRestoration(owner: MiniAppID, admitted: Bool) {
        guard admitted else { return }
        var state = state(for: owner, admitted: true)
        state.admitted = true
        owners[owner] = state
    }

    public func connect(owner: MiniAppID, token: UUID,
                        receive: @escaping @MainActor @Sendable (MiniAppBluetoothEvent) -> Void) {
        var state = state(for: owner, admitted: true)
        if let consumer = state.consumer, consumer.token != token {
            state.native.stopAll(); state.connections.removeAll()
        }
        state.consumer = Consumer(token: token, receive: receive)
        state.admitted = true
        owners[owner] = state
    }

    public func isConnected(owner: MiniAppID, token: UUID) -> Bool {
        owners[owner]?.consumer?.token == token
    }

    public func disconnect(owner: MiniAppID, token: UUID) {
        guard var state = owners[owner], state.consumer?.token == token else { return }
        state.consumer = nil
        state.connections.removeAll()
        state.native.stopAll()
        owners[owner] = state
    }

    public func unregister(owner: MiniAppID) {
        guard let state = owners.removeValue(forKey: owner) else { return }
        state.native.stopAll()
        state.native.eventHandler = nil
    }

    /// Querying status must not construct a manager and accidentally opt a
    /// disabled owner into native restoration.
    public func power(owner: MiniAppID) -> MiniAppBluetoothPower { owners[owner]?.native.power ?? .unknown }
    public func authorization(owner: MiniAppID) -> MiniAppBluetoothAuthorization {
        owners[owner]?.native.authorization ?? .notDetermined
    }

    public func scan(owner: MiniAppID, serviceUUIDs: [String]?, allowDuplicates: Bool) throws {
        let native = try active(owner).native
        try requireAvailable(native)
        native.scan(serviceUUIDs: serviceUUIDs, allowDuplicates: allowDuplicates)
    }
    public func stopScan(owner: MiniAppID) throws { try active(owner).native.stopScan() }

    public func connect(owner: MiniAppID, peripheral: UUID) throws -> MiniAppBluetoothConnection {
        var state = try active(owner)
        try requireAvailable(state.native)
        if let old = state.connections[peripheral] { state.native.disconnect(peripheral: peripheral, generation: old) }
        let generation = UUID()
        state.connections[peripheral] = generation
        owners[owner] = state
        state.native.connect(peripheral: peripheral, generation: generation)
        return .init(owner: owner, peripheral: peripheral, generation: generation)
    }

    public func disconnect(_ connection: MiniAppBluetoothConnection) throws {
        var state = try checked(connection)
        state.connections.removeValue(forKey: connection.peripheral)
        owners[connection.owner] = state
        state.native.disconnect(peripheral: connection.peripheral, generation: connection.generation)
    }

    public func discoverServices(_ identifiers: [String]?, on connection: MiniAppBluetoothConnection) throws {
        let state = try checked(connection)
        state.native.discoverServices(identifiers, peripheral: connection.peripheral, generation: connection.generation)
    }
    public func discoverCharacteristics(_ identifiers: [String]?, service: String,
                                        on connection: MiniAppBluetoothConnection) throws {
        let state = try checked(connection)
        state.native.discoverCharacteristics(identifiers, service: service, peripheral: connection.peripheral,
                                             generation: connection.generation)
    }
    public func read(_ characteristic: MiniAppBluetoothCharacteristic,
                     on connection: MiniAppBluetoothConnection) throws {
        let state = try checked(connection)
        state.native.read(characteristic, peripheral: connection.peripheral, generation: connection.generation)
    }
    public func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic,
                      type: MiniAppBluetoothWriteType, on connection: MiniAppBluetoothConnection) throws {
        let state = try checked(connection)
        state.native.write(data, to: characteristic, type: type, peripheral: connection.peripheral,
                           generation: connection.generation)
    }
    public func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic,
                          on connection: MiniAppBluetoothConnection) throws {
        let state = try checked(connection)
        state.native.setNotify(enabled, for: characteristic, peripheral: connection.peripheral,
                               generation: connection.generation)
    }

    private func state(for owner: MiniAppID, admitted: Bool) -> OwnerState {
        if let state = owners[owner] { return state }
        let native = factory(owner, Self.restorationIdentifier(for: owner))
        let state = OwnerState(native: native, admitted: admitted)
        owners[owner] = state
        native.eventHandler = { [weak self] event in self?.receive(event, owner: owner) }
        return owners[owner] ?? state
    }
    private func active(_ owner: MiniAppID) throws -> OwnerState {
        guard let state = owners[owner], state.admitted, state.consumer != nil else {
            throw MiniAppBluetoothFailure.stopped
        }
        return state
    }
    private func checked(_ connection: MiniAppBluetoothConnection) throws -> OwnerState {
        let state = try active(connection.owner)
        guard state.connections[connection.peripheral] == connection.generation else {
            throw MiniAppBluetoothFailure.staleGeneration
        }
        return state
    }
    private func requireAvailable(_ native: any MiniAppBluetoothNativeCentral) throws {
        guard native.authorization != .denied && native.authorization != .restricted else {
            throw MiniAppBluetoothFailure.permissionDenied(native.authorization)
        }
        guard native.power == .poweredOn else { throw MiniAppBluetoothFailure.bluetoothUnavailable(native.power) }
    }
    private func receive(_ event: MiniAppBluetoothEvent, owner: MiniAppID) {
        guard var state = owners[owner], state.admitted else { return }
        switch event {
        case .connected(let peripheral, let generation, _):
            guard state.connections[peripheral] == generation || state.connections[peripheral] == nil else { return }
            // A restored connection is adopted only for an admitted owner.
            state.connections[peripheral] = generation
            owners[owner] = state
        case .disconnected(let peripheral, let generation, _):
            guard state.connections[peripheral] == generation else { return }
            state.connections.removeValue(forKey: peripheral); owners[owner] = state
        case .services(let peripheral, let generation, _),
             .characteristics(let peripheral, let generation, _, _),
             .value(let peripheral, let generation, _, _, _),
             .notificationChanged(let peripheral, let generation, _, _),
             .writeCompleted(let peripheral, let generation, _):
            guard state.connections[peripheral] == generation else { return }
        case .failed(let peripheral?, let generation?, _):
            guard state.connections[peripheral] == generation else { return }
        default: break
        }
        state.consumer?.receive(event)
    }
}

@MainActor
public final class MiniAppBluetoothService {
    public let owner: MiniAppID
    private let coordinator: MiniAppBluetoothCoordinator
    private var token: UUID?
    private weak var runtime: MiniAppRuntime?
    public var receive: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?

    public init(owner: MiniAppID, coordinator: MiniAppBluetoothCoordinator = .shared) {
        precondition(owner.isValid); self.owner = owner; self.coordinator = coordinator
    }
    public func prepareRestoration(admitted: Bool) { coordinator.prepareRestoration(owner: owner, admitted: admitted) }
    public func connect(to runtime: MiniAppRuntime) throws {
        let token = UUID(), coordinator = coordinator, owner = owner
        try runtime.onShutdownAsync { [weak self] in
            coordinator.disconnect(owner: owner, token: token)
            if self?.token == token { self?.token = nil; self?.runtime = nil }
        }
        coordinator.connect(owner: owner, token: token) { [weak self] event in self?.receive?(event) }
        self.token = token; self.runtime = runtime
    }
    public func unregisterAllOwned() { coordinator.unregister(owner: owner); token = nil; runtime = nil }
    private func requireConnection() throws {
        guard let token, runtime?.isClosed == false, coordinator.isConnected(owner: owner, token: token) else {
            throw MiniAppBluetoothFailure.stopped
        }
    }
    public var power: MiniAppBluetoothPower { coordinator.power(owner: owner) }
    public var authorization: MiniAppBluetoothAuthorization { coordinator.authorization(owner: owner) }
    public func scan(serviceUUIDs: [String]? = nil, allowDuplicates: Bool = false) throws {
        try requireConnection(); try coordinator.scan(owner: owner, serviceUUIDs: serviceUUIDs, allowDuplicates: allowDuplicates)
    }
    public func stopScan() throws { try requireConnection(); try coordinator.stopScan(owner: owner) }
    public func connect(peripheral: UUID) throws -> MiniAppBluetoothConnection {
        try requireConnection(); return try coordinator.connect(owner: owner, peripheral: peripheral)
    }
    public func disconnect(_ connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.disconnect(connection)
    }
    public func discoverServices(_ identifiers: [String]? = nil, on connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.discoverServices(identifiers, on: connection)
    }
    public func discoverCharacteristics(_ identifiers: [String]? = nil, service: String,
                                        on connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.discoverCharacteristics(identifiers, service: service, on: connection)
    }
    public func read(_ characteristic: MiniAppBluetoothCharacteristic, on connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.read(characteristic, on: connection)
    }
    public func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic,
                      type: MiniAppBluetoothWriteType, on connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.write(data, to: characteristic, type: type, on: connection)
    }
    public func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic,
                          on connection: MiniAppBluetoothConnection) throws {
        try requireConnection(); guard connection.owner == owner else { throw MiniAppBluetoothFailure.wrongOwner }
        try coordinator.setNotify(enabled, for: characteristic, on: connection)
    }
}
