import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBluetoothCoordinatorTests: XCTestCase {
    func testTwoOwnersUseDistinctManagersAndStoppingOneDoesNotCancelOther() async throws {
        let pool = FakeBluetoothPool()
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let a = MiniAppBluetoothService(owner: MiniAppID("ble-a"), coordinator: coordinator)
        let b = MiniAppBluetoothService(owner: MiniAppID("ble-b"), coordinator: coordinator)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        let peripheral = UUID()
        let connectionA = try a.connect(peripheral: peripheral)
        let connectionB = try b.connect(peripheral: peripheral)

        await runtimeA.shutdown()

        XCTAssertEqual(pool.central(for: a.owner).stopAllCount, 1)
        XCTAssertEqual(pool.central(for: b.owner).stopAllCount, 0)
        try b.discoverServices(nil, on: connectionB)
        XCTAssertEqual(pool.central(for: b.owner).discoveries, [connectionB.generation])
        XCTAssertNotEqual(connectionA.generation, connectionB.generation)
    }

    func testReplacementAndLateCallbacksAreGenerationChecked() throws {
        let pool = FakeBluetoothPool(), owner = MiniAppID("ble-generation")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        let events = BluetoothEventBox(); service.receive = { events.values.append($0) }
        let peripheral = UUID()
        let old = try service.connect(peripheral: peripheral)
        let current = try service.connect(peripheral: peripheral)
        let native = pool.central(for: owner)
        native.emit(.services(peripheral: peripheral, generation: old.generation, identifiers: ["OLD"]))
        native.emit(.services(peripheral: peripheral, generation: current.generation, identifiers: ["NEW"]))
        XCTAssertEqual(events.values, [.services(peripheral: peripheral, generation: current.generation, identifiers: ["NEW"])])
        XCTAssertThrowsError(try service.disconnect(old)) { XCTAssertEqual($0 as? MiniAppBluetoothFailure, .staleGeneration) }
    }

    func testDisconnectRemovesBeforeNativeCancelSoDuplicateCallbackIsIgnored() throws {
        let pool = FakeBluetoothPool(), owner = MiniAppID("ble-cancel")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        let events = BluetoothEventBox(); service.receive = { events.values.append($0) }
        let connection = try service.connect(peripheral: UUID())
        try service.disconnect(connection)
        pool.central(for: owner).emit(.disconnected(peripheral: connection.peripheral,
            generation: connection.generation, message: nil))
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertThrowsError(try service.read(.init(service: "s", characteristic: "c"), on: connection))
    }

    func testRestorationOnlyConstructsManagerForAdmittedOwner() {
        let pool = FakeBluetoothPool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let a = MiniAppID("ble-restore-a"), b = MiniAppID("ble-restore-b")
        coordinator.prepareRestoration(owner: a, admitted: true)
        coordinator.prepareRestoration(owner: b, admitted: false)
        XCTAssertEqual(pool.created, [a])
        XCTAssertEqual(pool.central(for: a).identifier, MiniAppBluetoothCoordinator.restorationIdentifier(for: a))
    }

    func testPowerAndPermissionGateNativeOperations() throws {
        let pool = FakeBluetoothPool(), owner = MiniAppID("ble-power")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        let native = pool.central(for: owner); native.power = .poweredOff
        XCTAssertThrowsError(try service.scan()) { XCTAssertEqual($0 as? MiniAppBluetoothFailure, .bluetoothUnavailable(.poweredOff)) }
        native.power = .poweredOn; native.authorization = .denied
        XCTAssertThrowsError(try service.scan()) { XCTAssertEqual($0 as? MiniAppBluetoothFailure, .permissionDenied(.denied)) }
    }

    func testFullOperationSurfacePreservesOwnerAndGeneration() throws {
        let pool = FakeBluetoothPool(), owner = MiniAppID("ble-operations")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        try service.scan(serviceUUIDs: ["180D"], allowDuplicates: true)
        let connection = try service.connect(peripheral: UUID())
        let characteristic = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        try service.discoverServices(["180D"], on: connection)
        try service.discoverCharacteristics(["2A37"], service: "180D", on: connection)
        try service.read(characteristic, on: connection)
        try service.write(Data([1]), to: characteristic, type: .withResponse, on: connection)
        try service.setNotify(true, for: characteristic, on: connection)
        XCTAssertEqual(pool.central(for: owner).operations,
            ["scan:180D:true", "connect", "services", "characteristics", "read", "write", "notify:true"])
    }

    func testEveryConnectionOperationRejectsAnotherOwner() throws {
        let pool = FakeBluetoothPool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let a = MiniAppBluetoothService(owner: MiniAppID("ble-guard-a"), coordinator: coordinator)
        let b = MiniAppBluetoothService(owner: MiniAppID("ble-guard-b"), coordinator: coordinator)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        let foreign = try b.connect(peripheral: UUID())
        let key = MiniAppBluetoothCharacteristic(service: "s", characteristic: "c")
        XCTAssertThrowsError(try a.read(key, on: foreign)) { XCTAssertEqual($0 as? MiniAppBluetoothFailure, .wrongOwner) }
        XCTAssertThrowsError(try a.write(Data(), to: key, type: .withResponse, on: foreign))
        XCTAssertThrowsError(try a.setNotify(true, for: key, on: foreign))
    }
}

@MainActor
private final class FakeBluetoothPool {
    var created: [MiniAppID] = []
    var values: [MiniAppID: FakeBluetoothCentral] = [:]
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { [unowned self] owner, identifier in
        self.created.append(owner); let central = FakeBluetoothCentral(identifier: identifier); self.values[owner] = central; return central
    }
    func central(for owner: MiniAppID) -> FakeBluetoothCentral { values[owner]! }
}

@MainActor
private final class FakeBluetoothCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn
    var authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    let identifier: String
    var stopAllCount = 0, discoveries: [UUID] = [], operations: [String] = []
    init(identifier: String) { self.identifier = identifier }
    func emit(_ event: MiniAppBluetoothEvent) { eventHandler?(event) }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) { operations.append("scan:\(serviceUUIDs?.joined() ?? "nil"):\(allowDuplicates)") }
    func stopScan() { operations.append("stopScan") }
    func connect(peripheral: UUID, generation: UUID) { operations.append("connect") }
    func disconnect(peripheral: UUID, generation: UUID) { operations.append("disconnect") }
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) { discoveries.append(generation); operations.append("services") }
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) { operations.append("characteristics") }
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) { operations.append("read") }
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) { operations.append("write") }
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) { operations.append("notify:\(enabled)") }
    func stopAll() { stopAllCount += 1 }
}

@MainActor private final class BluetoothEventBox { var values: [MiniAppBluetoothEvent] = [] }
