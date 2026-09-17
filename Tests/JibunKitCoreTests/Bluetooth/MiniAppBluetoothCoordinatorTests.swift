import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBluetoothCoordinatorTests: XCTestCase {
    func testStopClosesDeliveryBeforeJoiningNativeAndPreservesOtherOwner() async throws {
        let pool = FakePool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let a = MiniAppBluetoothService(owner: MiniAppID("ble-a"), coordinator: coordinator)
        let b = MiniAppBluetoothService(owner: MiniAppID("ble-b"), coordinator: coordinator)
        let ra = MiniAppRuntime(), rb = MiniAppRuntime(); try a.connect(to: ra); try b.connect(to: rb)
        let events = EventBox(); a.receive = { events.values.append($0) }
        let ca = try await a.connect(peripheral: UUID()), cb = try await b.connect(peripheral: UUID())
        pool[a.owner].blockStop = true
        let stopping = Task { @MainActor in await ra.shutdown() }
        await pool[a.owner].stopEntered.wait()
        pool[a.owner].emit(.connected(peripheral: ca.peripheral, generation: ca.generation, restored: false))
        XCTAssertTrue(events.values.isEmpty)
        try b.discoverServices(nil, on: cb)
        pool[a.owner].releaseStop.open(); await stopping.value
        XCTAssertEqual(pool[b.owner].stopCount, 0)
    }

    func testNormalLateConnectedNeverReAdoptsAfterExplicitDisconnect() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-late"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime()
        try service.connect(to: runtime); let events = EventBox(); service.receive = { events.values.append($0) }
        let connection = try await service.connect(peripheral: UUID()); try await service.disconnect(connection)
        pool[owner].emit(.connected(peripheral: connection.peripheral, generation: connection.generation, restored: false))
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertThrowsError(try service.read(.init(service: "s", characteristic: "c"), on: connection))
    }

    func testReconnectJoinsOldNativeGenerationBeforeStartingNew() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-reconnect"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime(); try service.connect(to: runtime)
        let events = EventBox(); service.receive = { events.values.append($0) }
        let peripheral = UUID(), first = try await service.connect(peripheral: peripheral)
        pool[owner].blockDisconnect = true
        let task = Task { @MainActor in try await service.connect(peripheral: peripheral) }
        await pool[owner].disconnectEntered.wait()
        XCTAssertEqual(pool[owner].connectGenerations, [first.generation])
        pool[owner].releaseDisconnect.open(); let second = try await task.value
        XCTAssertEqual(pool[owner].connectGenerations, [first.generation, second.generation])
        pool[owner].emit(.services(peripheral: peripheral, generation: first.generation, identifiers: ["OLD"]))
        pool[owner].emit(.services(peripheral: peripheral, generation: second.generation, identifiers: ["NEW"]))
        XCTAssertEqual(events.values, [.services(peripheral: peripheral, generation: second.generation, identifiers: ["NEW"])])
    }

    func testColdRestoreStartsLifetimeAndSnapshotWaitsForConsumer() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-restore"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let lifetime = MiniAppFeatureLifetime(id: owner) { runtime in try service.connect(to: runtime) }
        let events = EventBox(); service.receive = { events.values.append($0) }
        service.prepareRestoration(admitted: true) { Task { try? await lifetime.start() } }
        let peripheral = UUID(), generation = UUID()
        pool[owner].emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        for _ in 0..<20 where lifetime.state != .running { await Task.yield() }
        XCTAssertEqual(lifetime.state, .running)
        XCTAssertEqual(events.values, [.connected(peripheral: peripheral, generation: generation, restored: true)])
        await lifetime.stop()
    }

    func testDisabledRestoreDoesNotConstructManager() {
        let pool = FakePool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        coordinator.prepareRestoration(owner: MiniAppID("disabled"), admitted: false, onRestore: {})
        XCTAssertTrue(pool.created.isEmpty)
    }

    func testOldServiceCannotUnregisterReplacementLease() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-lease"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let old = MiniAppBluetoothService(owner: owner, coordinator: coordinator), replacement = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let oldRuntime = MiniAppRuntime(), newRuntime = MiniAppRuntime(); try old.connect(to: oldRuntime); try replacement.connect(to: newRuntime)
        await old.unregisterAllOwned()
        _ = try await replacement.connect(peripheral: UUID())
        XCTAssertEqual(pool[owner].stopCount, 0)
        await newRuntime.shutdown()
    }

    func testPowerPermissionAndWriteBackpressureAreVisible() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-write"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime(); try service.connect(to: runtime)
        pool[owner].power = .poweredOff
        XCTAssertThrowsError(try service.scan())
        pool[owner].power = .poweredOn; let c = try await service.connect(peripheral: UUID())
        pool[owner].writeFailure = .writeWouldBlock(maximum: 20)
        XCTAssertThrowsError(try service.write(Data([1]), to: .init(service: "s", characteristic: "c"), type: .withoutResponse, on: c)) {
            XCTAssertEqual($0 as? MiniAppBluetoothFailure, .writeWouldBlock(maximum: 20))
        }
    }

    func testAdvertisementSnapshotPreservesBinaryStandardFields() {
        let snapshot = MiniAppBluetoothAdvertisement(localName: "sensor", manufacturerData: Data([0, 255]),
            serviceData: ["180D": Data([1, 2])], serviceUUIDs: ["180D"], txPower: -4, isConnectable: true)
        XCTAssertEqual(snapshot.manufacturerData, Data([0, 255]))
        XCTAssertEqual(snapshot.serviceData["180D"], Data([1, 2]))
    }
}

@MainActor private final class FakePool {
    var created: [MiniAppID] = []; var values: [MiniAppID: FakeCentral] = [:]
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { [unowned self] owner, _ in self.created.append(owner); let value = FakeCentral(); self.values[owner] = value; return value }
    subscript(_ owner: MiniAppID) -> FakeCentral { values[owner]! }
}
@MainActor private final class FakeCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn, authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    var blockStop = false, blockDisconnect = false, stopCount = 0
    var connectGenerations: [UUID] = [], writeFailure: MiniAppBluetoothFailure?
    let stopEntered = Gate(), disconnectEntered = Gate(), releaseStop = Gate(), releaseDisconnect = Gate()
    func emit(_ event: MiniAppBluetoothEvent) { eventHandler?(event) }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    func stopScan() {}
    func connect(peripheral: UUID, generation: UUID) { connectGenerations.append(generation) }
    func disconnect(peripheral: UUID, generation: UUID) async { disconnectEntered.open(); if blockDisconnect { await releaseDisconnect.wait() } }
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) throws { if let writeFailure { throw writeFailure } }
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func stopAll() async { stopCount += 1; stopEntered.open(); if blockStop { await releaseStop.wait() } }
}
@MainActor private final class Gate {
    var openState = false; var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if openState { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { openState = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
}
@MainActor private final class EventBox { var values: [MiniAppBluetoothEvent] = [] }
