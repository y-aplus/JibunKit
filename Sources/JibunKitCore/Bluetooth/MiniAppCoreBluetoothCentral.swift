import Foundation
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth

@MainActor
public final class MiniAppCoreBluetoothCentral: NSObject, MiniAppBluetoothNativeCentral,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    public var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)? {
        didSet {
            guard let eventHandler else { return }
            let pending = pendingEvents; pendingEvents.removeAll()
            for event in pending { eventHandler(event) }
        }
    }
    public private(set) var restorationIdentifier: String
    public let owner: MiniAppID
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var generations: [UUID: UUID] = [:]
    private var pendingReconnects: [UUID: UUID] = [:]
    private var services: [UUID: [String: CBService]] = [:]
    private var characteristics: [UUID: [MiniAppBluetoothCharacteristic: CBCharacteristic]] = [:]
    private var pendingEvents: [MiniAppBluetoothEvent] = []

    public init(owner: MiniAppID, restorationIdentifier: String) {
        self.owner = owner; self.restorationIdentifier = restorationIdentifier
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationIdentifier])
    }
    public var power: MiniAppBluetoothPower { Self.power(central.state) }
    public var authorization: MiniAppBluetoothAuthorization {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .allowedAlways: .allowed
        @unknown default: .unsupported
        }
    }
    public func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {
        central.scanForPeripherals(withServices: serviceUUIDs?.map { CBUUID(string: $0) },
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates])
    }
    public func stopScan() { central.stopScan() }
    public func connect(peripheral id: UUID, generation: UUID) {
        guard let peripheral = peripheral(id) else {
            return emit(.disconnected(peripheral: id, generation: generation,
                                      message: "Peripheral is not known to this owner"))
        }
        if generations[id] != nil {
            pendingReconnects[id] = generation
            central.cancelPeripheralConnection(peripheral)
            return
        }
        generations[id] = generation; peripheral.delegate = self; central.connect(peripheral)
    }
    public func disconnect(peripheral id: UUID, generation: UUID) {
        guard generations[id] == generation else { return }
        if let peripheral = peripherals[id] { central.cancelPeripheralConnection(peripheral) }
        else { clear(id) }
    }
    public func discoverServices(_ ids: [String]?, peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation) else { return }
        peripheral.discoverServices(ids?.map { CBUUID(string: $0) })
    }
    public func discoverCharacteristics(_ ids: [String]?, service: String, peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let service = services[id]?[service] else {
            return fail(id, generation, "Service is not known")
        }
        peripheral.discoverCharacteristics(ids?.map { CBUUID(string: $0) }, for: service)
    }
    public func read(_ key: MiniAppBluetoothCharacteristic, peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            return fail(id, generation, "Characteristic is not known")
        }
        peripheral.readValue(for: characteristic)
    }
    public func write(_ data: Data, to key: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
                      peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            return fail(id, generation, "Characteristic is not known")
        }
        let nativeType: CBCharacteristicWriteType
        switch type { case .withResponse: nativeType = .withResponse; case .withoutResponse: nativeType = .withoutResponse }
        peripheral.writeValue(data, for: characteristic, type: nativeType)
    }
    public func setNotify(_ enabled: Bool, for key: MiniAppBluetoothCharacteristic,
                          peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            return fail(id, generation, "Characteristic is not known")
        }
        peripheral.setNotifyValue(enabled, for: characteristic)
    }
    public func stopAll() {
        central.stopScan()
        for peripheral in peripherals.values where peripheral.state != .disconnected {
            central.cancelPeripheralConnection(peripheral)
        }
        generations.removeAll(); pendingReconnects.removeAll(); services.removeAll(); characteristics.removeAll()
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit(.powerChanged(Self.power(central.state), authorization: authorization))
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral; peripheral.delegate = self
        let safe = advertisementData.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = String(describing: entry.value)
        }
        emit(.discovered(.init(id: peripheral.identifier, name: peripheral.name,
                               rssi: RSSI.intValue, advertisement: safe)))
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let generation = generations[peripheral.identifier] else { return }
        emit(.connected(peripheral: peripheral.identifier, generation: generation, restored: false))
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                               error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        let pending = pendingReconnects.removeValue(forKey: peripheral.identifier)
        clear(peripheral.identifier)
        emit(.disconnected(peripheral: peripheral.identifier, generation: generation,
                           message: error?.localizedDescription ?? "Connect failed"))
        if let pending {
            generations[peripheral.identifier] = pending
            central.connect(peripheral)
        }
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        let pending = pendingReconnects.removeValue(forKey: peripheral.identifier)
        clear(peripheral.identifier)
        emit(.disconnected(peripheral: peripheral.identifier, generation: generation,
                           message: error?.localizedDescription))
        if let pending {
            generations[peripheral.identifier] = pending
            central.connect(peripheral)
        }
    }
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            let generation = UUID(); peripherals[peripheral.identifier] = peripheral
            generations[peripheral.identifier] = generation; peripheral.delegate = self
            emit(.connected(peripheral: peripheral.identifier, generation: generation, restored: true))
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let found = peripheral.services ?? []; services[peripheral.identifier] = Dictionary(uniqueKeysWithValues: found.map { ($0.uuid.uuidString, $0) })
        emit(.services(peripheral: peripheral.identifier, generation: generation,
                       identifiers: found.map { $0.uuid.uuidString }))
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                           error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let found = service.characteristics ?? []
        var map = characteristics[peripheral.identifier] ?? [:]
        for value in found { map[.init(service: service.uuid.uuidString, characteristic: value.uuid.uuidString)] = value }
        characteristics[peripheral.identifier] = map
        emit(.characteristics(peripheral: peripheral.identifier, generation: generation,
            service: service.uuid.uuidString, identifiers: found.map { $0.uuid.uuidString }))
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        emit(.value(peripheral: peripheral.identifier, generation: generation, characteristic: key,
                    data: characteristic.value ?? Data(), notifying: characteristic.isNotifying))
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        emit(.writeCompleted(peripheral: peripheral.identifier, generation: generation, characteristic: key))
    }
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        emit(.notificationChanged(peripheral: peripheral.identifier, generation: generation,
                                  characteristic: key, enabled: characteristic.isNotifying))
    }
    private func peripheral(_ id: UUID) -> CBPeripheral? {
        if let value = peripherals[id] { return value }
        let value = central.retrievePeripherals(withIdentifiers: [id]).first
        if let value { peripherals[id] = value; value.delegate = self }
        return value
    }
    private func checked(_ id: UUID, _ generation: UUID) -> CBPeripheral? {
        guard generations[id] == generation else { fail(id, generation, "Stale connection generation"); return nil }
        return peripheral(id)
    }
    private func clear(_ id: UUID) { generations[id] = nil; services[id] = nil; characteristics[id] = nil }
    private func fail(_ id: UUID?, _ generation: UUID?, _ message: String) {
        emit(.failed(peripheral: id, generation: generation, message: message))
    }
    private func emit(_ event: MiniAppBluetoothEvent) {
        if let eventHandler { eventHandler(event) } else { pendingEvents.append(event) }
    }
    private static func power(_ state: CBManagerState) -> MiniAppBluetoothPower {
        switch state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}
#else
@MainActor
public final class MiniAppCoreBluetoothCentral: MiniAppBluetoothNativeCentral {
    public var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    public let owner: MiniAppID
    public let restorationIdentifier: String
    public init(owner: MiniAppID, restorationIdentifier: String) { self.owner = owner; self.restorationIdentifier = restorationIdentifier }
    public var power: MiniAppBluetoothPower { .unsupported }
    public var authorization: MiniAppBluetoothAuthorization { .unsupported }
    public func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    public func stopScan() {}
    public func connect(peripheral: UUID, generation: UUID) {}
    public func disconnect(peripheral: UUID, generation: UUID) {}
    public func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    public func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    public func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    public func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) {}
    public func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    public func stopAll() {}
}
#endif
