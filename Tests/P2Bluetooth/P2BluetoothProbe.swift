#if os(iOS)
import SwiftUI
import JibunKitCore

@MainActor
enum P2BluetoothProbe {
    static let sensor = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-sensor"), title: "BLE Sensor")
    static let accessory = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-accessory"), title: "BLE Accessory")
    static var definitions: [MiniAppDefinition] { [sensor.definition, accessory.definition] }
}

enum P2BluetoothDiagnosticInput {
    static func normalizedUUID(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: value) { return uuid.uuidString }
        guard [4, 8, 32].contains(value.count), value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value.uppercased()
    }

    static func data(hex input: String) -> Data? {
        let value = input.filter { !$0.isWhitespace }
        guard !value.isEmpty, value.count.isMultiple(of: 2), value.allSatisfy({ $0.isHexDigit }) else { return nil }
        var data = Data(), index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else { return nil }
            data.append(byte); index = end
        }
        return data
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
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
    @Published var serviceUUID = "180D"
    @Published var characteristicUUID = "2A37"
    @Published var writeHex = "01"
    @Published private(set) var discoveredServices: [String] = []
    @Published private(set) var discoveredCharacteristics: [String] = []
    @Published private(set) var lastReadHex = "未受信"
    @Published private(set) var lastNotifyHex = "未受信"
    @Published private(set) var writeResult = "未送信"
    @Published private(set) var notifyResult = "未設定"
    private var awaitingRead = false

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
    func selectService(_ value: String) { serviceUUID = value }
    func selectCharacteristic(_ value: String) { characteristicUUID = value }
    func discoverAllServices() { report { guard let connection = requireConnection() else { return }; try service.discoverServices(nil, on: connection) } }
    func discover() {
        guard let serviceID = validUUID(serviceUUID, label: "Service UUID") else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverServices([serviceID], on: connection) }
    }
    func discoverCharacteristic() {
        guard let key = diagnosticCharacteristic() else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverCharacteristics([key.characteristic], service: key.service, on: connection) }
    }
    func discoverAllCharacteristics() {
        guard let serviceID = validUUID(serviceUUID, label: "Service UUID") else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverCharacteristics(nil, service: serviceID, on: connection) }
    }
    func read() {
        guard let key = diagnosticCharacteristic() else { lastReadHex = status; return }
        report { guard let connection = requireConnection() else { return }; awaitingRead = true; try service.read(key, on: connection); status = "Read要求送信済み" }
    }
    func write() {
        guard let key = diagnosticCharacteristic() else { writeResult = status; return }
        guard let data = P2BluetoothDiagnosticInput.data(hex: writeHex) else {
            writeResult = "拒否: 送信bytesは空でない偶数桁のhex（空白区切り可）"; status = writeResult; return
        }
        do {
            guard let connection = requireConnection() else { return }
            writeResult = "応答待ち（\(data.count) bytes）"
            try service.write(data, to: key, type: .withResponse, on: connection)
        } catch { writeResult = "送信拒否/失敗: \(error)"; status = writeResult }
    }
    func subscribe(_ enabled: Bool) {
        guard let key = diagnosticCharacteristic() else { notifyResult = status; return }
        do {
            guard let connection = requireConnection() else { return }
            notifyResult = enabled ? "購読開始応答待ち" : "購読解除応答待ち"
            try service.setNotify(enabled, for: key, on: connection)
        } catch { notifyResult = "Notify拒否/失敗: \(error)"; status = notifyResult }
    }
    private func receive(_ event: MiniAppBluetoothEvent) {
        switch event {
        case .discovered(let peripheral):
            if let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) { peripherals[index] = peripheral }
            else { peripherals.append(peripheral) }
        case .connected(let peripheral, _, let restored):
            if restored {
                do {
                    if let restoredConnection = try service.currentConnection(peripheral: peripheral) {
                        connection = restoredConnection; status = "復元接続済み（診断操作可能）"
                    } else {
                        status = "復元connected通知を受信したが操作用connection ticketなし"
                    }
                } catch { status = "復元connection取得失敗: \(error)" }
            } else { status = "接続済み" }
        case .disconnected: status = "切断済み"; connection = nil; awaitingRead = false
        case .powerChanged(let power, _): status = "電源: \(power.rawValue)"
        case .services(_, _, let identifiers):
            discoveredServices = identifiers; status = "Service候補 \(identifiers.count)件"
        case .characteristics(_, _, let service, let identifiers):
            discoveredCharacteristics = identifiers; status = "\(service) のCharacteristic候補 \(identifiers.count)件"
        case .value(_, _, let characteristic, let data, let notifying):
            let value = P2BluetoothDiagnosticInput.hex(data)
            if awaitingRead { lastReadHex = "\(characteristic.characteristic): \(value)"; awaitingRead = false }
            if notifying { lastNotifyHex = "\(characteristic.characteristic): \(value)" }
            status = "値受信 \(data.count) bytes"
        case .writeCompleted(_, _, let characteristic):
            writeResult = "成功: \(characteristic.characteristic)"; status = "Write応答成功"
        case .notificationChanged(_, _, let characteristic, let enabled):
            notifyResult = "\(characteristic.characteristic): \(enabled ? "購読中" : "未購読")"; status = "Notify状態更新"
        case .readyToWriteWithoutResponse(_, _, let maximum): status = "Write without response再開可（最大\(maximum) bytes）"
        case .failed(_, _, let message):
            status = "失敗: \(message)"
            awaitingRead = false
            if writeResult.hasPrefix("応答待ち") { writeResult = "失敗: \(message)" }
            if notifyResult.hasSuffix("応答待ち") { notifyResult = "失敗: \(message)" }
        default: break
        }
    }
    private func validUUID(_ value: String, label: String) -> String? {
        guard let normalized = P2BluetoothDiagnosticInput.normalizedUUID(value) else {
            status = "拒否: \(label)は4/8/32桁hexまたは128-bit UUIDで指定"; return nil
        }
        return normalized
    }
    private func diagnosticCharacteristic() -> MiniAppBluetoothCharacteristic? {
        guard let service = validUUID(serviceUUID, label: "Service UUID"),
              let characteristic = validUUID(characteristicUUID, label: "Characteristic UUID") else { return nil }
        return .init(service: service, characteristic: characteristic)
    }
    private func requireConnection() -> MiniAppBluetoothConnection? {
        guard let connection else { status = "拒否: 操作可能な通常connectionがありません"; return nil }
        return connection
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
            Section("GATT指定") {
                TextField("Service UUID", text: $feature.serviceUUID)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                HStack {
                    Button("全Service検索") { feature.discoverAllServices() }
                    Button("指定Service検索") { feature.discover() }
                }
                if feature.discoveredServices.isEmpty { Text("Service候補: 未取得") }
                ForEach(feature.discoveredServices, id: \.self) { value in
                    Button("Service候補: \(value)") { feature.selectService(value) }
                }
                TextField("Characteristic UUID", text: $feature.characteristicUUID)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                HStack {
                    Button("全Characteristic検索") { feature.discoverAllCharacteristics() }
                    Button("指定Characteristic検索") { feature.discoverCharacteristic() }
                }
                if feature.discoveredCharacteristics.isEmpty { Text("Characteristic候補: 未取得") }
                ForEach(feature.discoveredCharacteristics, id: \.self) { value in
                    Button("Characteristic候補: \(value)") { feature.selectCharacteristic(value) }
                }
            }
            Section("値診断") {
                TextField("送信bytes hex（例: 01 FF）", text: $feature.writeHex)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                HStack { Button("Read") { feature.read() }; Button("Write with response") { feature.write() } }
                HStack { Button("Subscribe") { feature.subscribe(true) }; Button("Unsubscribe") { feature.subscribe(false) } }
                LabeledContent("Read結果", value: feature.lastReadHex)
                LabeledContent("Write結果", value: feature.writeResult)
                LabeledContent("Notify状態", value: feature.notifyResult)
                LabeledContent("Notify受信値", value: feature.lastNotifyHex)
            }
        }
    }
}
#endif
