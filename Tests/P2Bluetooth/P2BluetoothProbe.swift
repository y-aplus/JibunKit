#if os(iOS)
import SwiftUI
import JibunKitCore

@MainActor
enum P2BluetoothProbe {
    static let sensor = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-sensor"), title: "BLE Sensor")
    static let accessory = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-accessory"), title: "BLE Accessory")
    static var definitions: [MiniAppDefinition] { [sensor.definition, accessory.definition] }
}

@MainActor
final class P2BluetoothFeature: ObservableObject {
    let id: MiniAppID, title: String
    let service: MiniAppBluetoothService
    let consents: MiniAppConsentStore
    let lifetime: MiniAppFeatureLifetime
    @Published var status = "停止中"
    @Published var peripherals: [MiniAppBluetoothPeripheral] = []
    @Published private(set) var connection: MiniAppBluetoothConnection?
    private let diagnostic = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")

    init(id: MiniAppID, title: String, coordinator: MiniAppBluetoothCoordinator = .shared,
         consents: MiniAppConsentStore = MiniAppConsentStore(defaults: .standard)) {
        self.id = id; self.title = title; self.consents = consents
        let service = MiniAppBluetoothService(owner: id, coordinator: coordinator)
        self.service = service
        lifetime = MiniAppFeatureLifetime(id: id) { [service, consents, id] runtime in
            guard consents.consent(for: id, permissionID: "bluetooth") == .allowed else {
                throw MiniAppBluetoothFailure.permissionDenied(.notDetermined)
            }
            try await service.connect(to: runtime)
        }
        service.receive = { [weak self] event in self?.receive(event) }
    }
    var definition: MiniAppDefinition {
        MiniAppDefinition(id: id, title: title, systemImage: "antenna.radiowaves.left.and.right",
            lifetime: lifetime,
            permissions: [.init(id: "bluetooth", title: "Bluetooth", purpose: "近くのBLE機器に接続します", deniedBehavior: "スキャンと接続を開始しません")],
            onConsentChange: { [weak self] permission, decision in
                guard let self, permission == "bluetooth" else { return }
                self.lifetime.setStartAllowed(decision == .allowed)
                if decision != .allowed {
                    Task { await self.lifetime.stop(); await self.service.unregisterAllOwned() }
                }
            },
            onUnregister: { [weak self] in await self?.service.unregisterAllOwned() },
            onHostLaunch: { [weak self] in
                guard let self else { return }
                let admitted = self.lifetime.isStartAllowed && self.consents.consent(for: self.id, permissionID: "bluetooth") == .allowed
                self.service.prepareRestoration(admitted: admitted) { [weak self] in
                    guard let self else { return }
                    Task { try? await self.lifetime.start() }
                }
            }
        ) { [self] _ in P2BluetoothView(feature: self) }
    }
    func scan() { report { try service.scan(); status = "スキャン中" } }
    func stopScan() { report { try service.stopScan(); status = "スキャン停止" } }
    func connect(_ peripheral: MiniAppBluetoothPeripheral) { reportAsync { self.connection = try await self.service.connect(peripheral: peripheral.id) } }
    func disconnect() { reportAsync { if let connection = self.connection { try await self.service.disconnect(connection); self.connection = nil } } }
    func discover() { report { guard let connection else { return }; try service.discoverServices([diagnostic.service], on: connection) } }
    func discoverCharacteristic() { report { guard let connection else { return }; try service.discoverCharacteristics([diagnostic.characteristic], service: diagnostic.service, on: connection) } }
    func read() { report { guard let connection else { return }; try service.read(diagnostic, on: connection) } }
    func write() { report { guard let connection else { return }; try service.write(Data([1]), to: diagnostic, type: .withResponse, on: connection) } }
    func subscribe(_ enabled: Bool) { report { guard let connection else { return }; try service.setNotify(enabled, for: diagnostic, on: connection) } }
    private func receive(_ event: MiniAppBluetoothEvent) {
        switch event {
        case .discovered(let peripheral):
            if let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) { peripherals[index] = peripheral }
            else { peripherals.append(peripheral) }
        case .connected(_, _, let restored): status = restored ? "復元接続" : "接続済み"
        case .disconnected: status = "切断済み"; connection = nil
        case .powerChanged(let power, _): status = "電源: \(power.rawValue)"
        case .failed(_, _, let message): status = "失敗: \(message)"
        default: break
        }
    }
    private func report(_ body: () throws -> Void) { do { try body() } catch { status = "拒否/失敗: \(error)" } }
    private func reportAsync(_ body: @escaping @MainActor () async throws -> Void) {
        Task { do { try await body() } catch { status = "拒否/失敗: \(error)" } }
    }
}

private struct P2BluetoothView: View {
    @ObservedObject var feature: P2BluetoothFeature
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.bluetooth.\(feature.id.rawValue).status")
            HStack { Button("スキャン") { feature.scan() }; Button("停止") { feature.stopScan() } }
            ForEach(feature.peripherals) { peripheral in
                Button(peripheral.name ?? peripheral.id.uuidString) { feature.connect(peripheral) }
            }
            Button("切断") { feature.disconnect() }
            Button("Service discovery (180D)") { feature.discover() }
            Button("Characteristic discovery (2A37)") { feature.discoverCharacteristic() }
            HStack {
                Button("Read") { feature.read() }; Button("Write") { feature.write() }
                Button("Subscribe") { feature.subscribe(true) }; Button("Unsubscribe") { feature.subscribe(false) }
            }
        }
    }
}
#endif
