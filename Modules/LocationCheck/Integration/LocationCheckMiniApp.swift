#if os(iOS)
import JibunKitCore
import SwiftUI
import UIKit

/// A device check for MiniAppLocationService (issue #20): one-time fixes,
/// significant-change and visit monitoring. Every event is kept in a log that
/// survives relaunch, with the app state it arrived in, so events that
/// relaunched the app in the background can be seen later.
@MainActor
enum LocationCheckMiniApp {
    static let id = MiniAppID("locationcheck")
    static let permissionID = "location"
    static let consents = MiniAppConsentStore(defaults: .standard)
    static let log = LocationCheckLog(files: try? MiniAppFiles.shared(context: MiniAppContext(id: id)))

    static let service: MiniAppLocationService = {
        let service = MiniAppLocationService(owner: id) {
            consents.consent(for: id, permissionID: permissionID) == .allowed
        }
        service.receive = { event in log.record(event) }
        service.receiveMonitorEvent = { event in log.record(event) }
        return service
    }()

    static let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
        try service.connect(to: runtime)
    }

    static let permission = MiniAppPermissionDeclaration(
        id: permissionID,
        title: "位置情報",
        purpose: "1回だけ現在地を取得し、大きな位置変化と訪問を記録します。",
        deniedBehavior: "iOSに許可を求めず、何も記録しません。"
    )

    static let definition = makeDefinition()

    private static func makeDefinition() -> MiniAppDefinition {
        MiniAppDefinition(
            id: id,
            title: "LocationCheck",
            systemImage: "location.viewfinder",
            lifetime: lifetime,
            externalAccess: service.externalAccess,
            permissions: [permission],
            onConsentChange: { permission, decision in
                guard permission == permissionID else { return }
                log.add("利用同意: \(decision.rawValue)")
                try service.featureConsentDidChange()
            },
            onUnregister: {
                try await MainActor.run {
                    try service.unregisterAllOwned()
                    log.clear()
                }
            },
            onHostLaunch: {
                log.add("アプリ起動（監視中: \(service.systemMonitors.map(\.rawValue).sorted().joined(separator: ", "))）")
                try service.reconnectPersistedMonitoring()
            }
        ) { _ in
            LocationCheckView()
        }
    }
}

@MainActor
@Observable
final class LocationCheckLog {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var state: String
        var text: String
    }

    private let files: MiniAppFiles?
    private static let name = "LocationCheckLog.json"
    private(set) var entries: [Entry]
    var persists: Bool { files != nil }

    init(files: MiniAppFiles?) {
        self.files = files
        if let data = try? files?.read(named: Self.name),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        } else {
            entries = []
        }
    }

    func add(_ text: String) {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        entries.insert(Entry(date: .now, state: state, text: text), at: 0)
        if entries.count > 300 { entries.removeLast(entries.count - 300) }
        do {
            try files?.prepareDirectory()
            try files?.write(JSONEncoder().encode(entries), named: Self.name)
        } catch {}
    }

    func clear() {
        entries = []
        if let url = try? files?.fileURL(named: Self.name) { try? FileManager.default.removeItem(at: url) }
    }

    func record(_ event: MiniAppLocationEvent) {
        switch event {
        case .locations(_, let samples):
            if let sample = samples.last {
                add("現在地 " + Self.describe(sample))
            } else {
                add("現在地: 位置なし")
            }
        case .failed(_, let message): add("測位失敗: \(message)")
        case .authorizationChanged(let value): add("iOSの許可: \(value.rawValue)")
        case .monitoringFailed(_, let message): add("監視失敗: \(message)")
        default: add("イベント: \(event)")
        }
    }

    func record(_ event: MiniAppLocationMonitorEvent) {
        switch event {
        case .significantChange(let samples):
            add("大きな位置変化: " + samples.map(Self.describe).joined(separator: " / "))
        case .visit(let visit):
            let arrival = visit.arrival.map { $0.formatted(date: .omitted, time: .shortened) } ?? "?"
            let departure = visit.departure.map { $0.formatted(date: .omitted, time: .shortened) } ?? "?"
            add(String(format: "訪問 %.4f, %.4f ±%.0fm 到着 %@ 出発 %@",
                       visit.latitude, visit.longitude, visit.horizontalAccuracy, arrival, departure))
        }
    }

    private static func describe(_ sample: MiniAppLocationSample) -> String {
        String(format: "%.4f, %.4f ±%.0fm at %@", sample.latitude, sample.longitude,
               sample.horizontalAccuracy, sample.timestamp.formatted(date: .omitted, time: .standard))
    }
}

private struct LocationCheckView: View {
    @Environment(\.miniAppConsentStore) private var consents
    @State private var message: String?
    @State private var monitors: Set<MiniAppLocationSystemMonitor> = []
    private let log = LocationCheckMiniApp.log
    private let service = LocationCheckMiniApp.service

    private var allowed: Bool {
        consents?.consent(for: LocationCheckMiniApp.id, permissionID: LocationCheckMiniApp.permissionID) == .allowed
    }

    var body: some View {
        Form {
            Section {
                Toggle("このミニアプリで位置情報を使う", isOn: Binding(get: { allowed }, set: { setConsent($0) }))
                Button("使用中の許可を求める") { perform { try service.requestAuthorization(.whenInUse) } }
                Button("「常に」の許可を求める") { perform { try service.requestAuthorization(.always) } }
                Text("iOSの許可: \(MiniAppLocationCoordinator.shared.authorization.rawValue)")
                    .font(.caption)
            } footer: {
                Text("アプリの終了後もイベントを受け取るには「常に」が必要です。（LocationCheck 第2版）")
            }
            Section("1回の測位") {
                Button("現在地を1回取得") {
                    perform {
                        _ = try service.requestLocation(desiredAccuracy: 50)
                        log.add("1回の測位を依頼")
                    }
                }
            }
            Section("監視") {
                monitorToggle(.significantChanges, title: "大きな位置変化")
                monitorToggle(.visits, title: "訪問")
            }
            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                ForEach(log.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text)
                        Text("\(entry.date.formatted(date: .abbreviated, time: .standard)) · \(entry.state)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(log.persists ? "ログ" : "ログ（保存できません。終了すると消えます）")
            } footer: {
                Button("ログを消す", role: .destructive) { log.clear() }
            }
        }
        .onAppear { monitors = service.systemMonitors }
    }

    private func monitorToggle(_ monitor: MiniAppLocationSystemMonitor, title: String) -> some View {
        Toggle(title, isOn: Binding(get: { monitors.contains(monitor) }, set: { on in
            perform {
                if on { try service.startMonitoring(monitor) } else { try service.stopMonitoring(monitor) }
                log.add("\(monitor.rawValue)の監視を\(on ? "開始" : "停止")")
            }
            monitors = service.systemMonitors
        }))
    }

    private func setConsent(_ on: Bool) {
        guard let consents else { return }
        perform {
            try LocationCheckMiniApp.definition.setConsent(on ? .allowed : .denied,
                                                           permissionID: LocationCheckMiniApp.permissionID,
                                                           in: consents)
        }
        monitors = service.systemMonitors
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            message = nil
        } catch {
            message = String(describing: error)
        }
    }
}
#endif
