#if os(iOS)
import JibunKitCore
import SwiftUI

@MainActor
enum P2LocationProbe {
    static let coordinator = MiniAppLocationCoordinator.shared
    static let tracker = P2LocationFeature(id: MiniAppID("p2-location-tracker"), coordinator: coordinator, kind: .tracker)
    static let regions = P2LocationFeature(id: MiniAppID("p2-location-regions"), coordinator: coordinator, kind: .regions)
    static var definitions: [MiniAppDefinition] { [tracker.definition, regions.definition] }
}

@MainActor
final class P2LocationFeature {
    enum Kind { case tracker, regions }
    let id: MiniAppID
    let kind: Kind
    let coordinator: MiniAppLocationCoordinator
    let state = P2LocationState()
    private var consentStore: MiniAppConsentStore?
    private var updateGeneration: UUID?
    lazy var service = MiniAppLocationService(owner: id, coordinator: coordinator) { [weak self] in
        guard let self else { return false }
        return self.consentStore?.consent(for: self.id, permissionID: "location") == .allowed
    }
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.service.connect(to: runtime)
        self.service.receive = { [weak self] in self?.receive($0) }
        self.state.generation += 1
        self.state.status = "Feature接続済み・OS許可 \(self.coordinator.authorization.rawValue)"
    }

    init(id: MiniAppID, coordinator: MiniAppLocationCoordinator, kind: Kind) {
        self.id = id; self.coordinator = coordinator; self.kind = kind
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: kind == .tracker ? "位置更新Probe" : "Region/iBeacon Probe",
            systemImage: kind == .tracker ? "location" : "mappin.and.ellipse",
            lifetime: lifetime,
            permissions: [.init(id: "location", title: "位置情報",
                                purpose: kind == .tracker ? "選択した精度で前景・背景の位置更新を受け取ります" : "geofenceとiBeaconの出入りを監視します",
                                deniedBehavior: "OS許可を要求せず、位置処理を開始しません")],
            onUnregister: { [weak self] in try self?.service.unregisterAll() },
            onHostLaunch: { [weak self] in self?.coordinator.reconnectPersistedMonitoring() }
        ) { [self] _ in P2LocationView(feature: self) }
    }

    func attachConsent(_ store: MiniAppConsentStore?) {
        consentStore = store
        report { try service.featureConsentDidChange() }
    }
    func request(_ request: MiniAppLocationAuthorizationRequest) { report { try service.requestAuthorization(request) } }
    func start(background: Bool) {
        report {
            updateGeneration = try service.startUpdates(.init(
                desiredAccuracy: background ? 10 : 100,
                distanceFilter: background ? 10 : 25,
                activityType: background ? .fitness : .other,
                pausesAutomatically: true,
                background: background,
                showsBackgroundIndicator: background
            ))
            state.status = background ? "背景位置更新を開始" : "前景位置更新を開始"
        }
    }
    func stopUpdates() {
        report {
            guard let updateGeneration else { return }
            try service.stopUpdates(generation: updateGeneration)
            self.updateGeneration = nil; state.status = "位置更新を停止"
        }
    }
    func registerGeofence() {
        report {
            let registration = try service.register(localID: "tokyo-station", region: .geofence(
                latitude: 35.681236, longitude: 139.767125, radius: 150,
                notifyOnEntry: true, notifyOnExit: true))
            state.lastRegistration = registration; state.status = "geofence登録 \(registration.localID)"
        }
    }
    func registerBeacon() {
        report {
            let registration = try service.register(localID: "diagnostic-beacon", region: .beacon(
                uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1, minor: 1,
                notifyOnEntry: true, notifyOnExit: true))
            state.lastRegistration = registration; state.status = "iBeacon監視登録 \(registration.localID)"
        }
    }
    func unregisterLast() {
        report {
            guard let registration = state.lastRegistration else { return }
            try service.unregister(localID: registration.localID, generation: registration.generation)
            state.lastRegistration = nil; state.status = "担当Regionを解除"
        }
    }
    private func receive(_ event: MiniAppLocationEvent) {
        state.eventCount += 1
        switch event {
        case .locations(_, let samples): state.status = "位置更新 \(samples.count)件"; state.lastSample = samples.last
        case .authorizationChanged(let value): state.status = "OS許可変更: \(value.rawValue)"
        case .entered(let value): state.status = "進入: \(value.localID)"
        case .exited(let value): state.status = "退出: \(value.localID)"
        case .state(let value, let regionState): state.status = "状態 \(value.localID): \(regionState)"
        case .monitoringFailed(_, let message), .failed(_, let message): state.status = "失敗: \(message)"
        }
    }
    private func report(_ operation: () throws -> Void) {
        do { try operation() } catch { state.status = "拒否/失敗: \(error)" }
    }
}

@MainActor
final class P2LocationState: ObservableObject {
    @Published var status = "未接続"
    @Published var eventCount = 0
    @Published var generation = 0
    @Published var lastSample: MiniAppLocationSample?
    @Published var lastRegistration: MiniAppLocationRegistration?
}

private struct P2LocationView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
    @ObservedObject var state: P2LocationState
    let feature: P2LocationFeature
    init(feature: P2LocationFeature) { self.feature = feature; state = feature.state }
    private var locationConsent: MiniAppConsent {
        consentStore?.consent(for: feature.id, permissionID: "location") ?? .notDetermined
    }
    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("p2.location.\(feature.id.rawValue).status")
            Text("event \(state.eventCount) / runtime世代 \(state.generation)")
            Button("When In Use許可を要求") { feature.request(.whenInUse) }
            Button("Always許可を要求") { feature.request(.always) }
            if feature.kind == .tracker {
                Button("前景位置更新") { feature.start(background: false) }
                Button("背景位置更新") { feature.start(background: true) }
                Button("位置更新停止") { feature.stopUpdates() }
            } else {
                Button("東京駅geofence登録") { feature.registerGeofence() }
                Button("診断iBeacon登録") { feature.registerBeacon() }
                Button("最後の担当Regionを解除") { feature.unregisterLast() }
            }
            if let sample = state.lastSample { Text("\(sample.latitude), \(sample.longitude) ±\(sample.horizontalAccuracy)m") }
        }
        .onAppear { feature.attachConsent(consentStore) }
        .onChange(of: locationConsent) { _, _ in feature.attachConsent(consentStore) }
    }
}
#endif
