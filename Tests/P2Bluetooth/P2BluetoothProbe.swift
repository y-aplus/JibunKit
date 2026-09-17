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
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [service] runtime in try service.connect(to: runtime) }
    @Published var status = "停止中"
    @Published var peripherals: [MiniAppBluetoothPeripheral] = []
    private var connection: MiniAppBluetoothConnection?

    init(id: MiniAppID, title: String, coordinator: MiniAppBluetoothCoordinator = .shared) {
        self.id = id; self.title = title; service = MiniAppBluetoothService(owner: id, coordinator: coordinator)
        service.receive = { [weak self] event in self?.receive(event) }
    }
    var definition: MiniAppDefinition {
        MiniAppDefinition(id: id, title: title, systemImage: "antenna.radiowaves.left.and.right",
            lifetime: lifetime,
            permissions: [.init(id: "bluetooth", title: "Bluetooth", purpose: "近くのBLE機器に接続します", deniedBehavior: "スキャンと接続を開始しません")],
            onConsentChange: { [weak self] permission, decision in
                guard permission == "bluetooth", decision != .allowed else { return }
                self?.service.unregisterAllOwned()
            },
            onUnregister: { [weak self] in self?.service.unregisterAllOwned() },
            onHostLaunch: { [weak self] in self?.service.prepareRestoration(admitted: self?.lifetime.isStartAllowed == true) }
        ) { [self] _ in P2BluetoothView(feature: self) }
    }
    func scan() { report { try service.scan(); status = "スキャン中" } }
    func stopScan() { report { try service.stopScan(); status = "スキャン停止" } }
    func connect(_ peripheral: MiniAppBluetoothPeripheral) { report { connection = try service.connect(peripheral: peripheral.id) } }
    func disconnect() { report { if let connection { try service.disconnect(connection); self.connection = nil } } }
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
        }
    }
}
#endif
