#if os(iOS)
import ActivityKit
import AlarmKit
import AppIntents
import ContinuingAlarmSupport
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureBAlarmMetadata: AlarmMetadata {
    public let owner: String
    public let localID: String
    public let generation: UUID
    public let registrationID: UUID
    public let routine: String
}

public struct FeatureBAlarmState: Codable, Sendable {
    public var stopEvents: Int
    public var completedDoses: Int
    public static let initial = Self(stopEvents: 0, completedDoses: 3)
}

public enum FeatureBAlarmModel: ContinuingAlarmFixtureFeature {
    public static let owner = MiniAppID("alarm-feature-b")
    public static let localID = "same-id"
    public static let title: LocalizedStringResource = "B: 服薬を確認"
    public static let tint = Color.blue
    public static let initialState = FeatureBAlarmState.initial
    public static func metadata(identity: MiniAppContinuingIdentity) -> FeatureBAlarmMetadata {
        .init(owner: identity.owner, localID: identity.localID, generation: identity.generation,
              registrationID: identity.registrationID, routine: "夜の服薬")
    }
    public static func summary(_ state: FeatureBAlarmState) -> String {
        "服薬 \(state.completedDoses) / stop callback \(state.stopEvents)"
    }
    public static func recordSystemStop(_ state: inout FeatureBAlarmState) {
        state.stopEvents += 1; state.completedDoses += 1
    }
}

@available(iOS 26.0, *)
public final class FeatureBAlarmEnvironment: @unchecked Sendable {
    public static let shared = FeatureBAlarmEnvironment()
    private let lock = NSLock()
    private var cached: ContinuingAlarmFeatureService<FeatureBAlarmModel>?
    private init() {}
    public func service() throws -> ContinuingAlarmFeatureService<FeatureBAlarmModel> {
        try lock.withLock {
            if let cached { return cached }
            let store = try MiniAppSharedState<FeatureBAlarmState>.shared(owner: FeatureBAlarmModel.owner)
            let journal = try MiniAppContinuingJournal.shared(owner: FeatureBAlarmModel.owner, namespace: "alarmkit")
            let value = ContinuingAlarmFeatureService<FeatureBAlarmModel>(store: store, journal: journal)
            cached = value
            return value
        }
    }
}

@available(iOS 26.0, *)
public struct FeatureBAlarmStopIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Bの停止を記録"
    public static let openAppWhenRun = false
    @Parameter(title: "Owner") public var owner: String
    @Parameter(title: "Local ID") public var localID: String
    @Parameter(title: "Generation") public var generation: String
    @Parameter(title: "Registration") public var registrationID: String
    @Parameter(title: "Alarm") public var systemID: String
    public init() { owner = ""; localID = ""; generation = ""; registrationID = ""; systemID = "" }
    public init(identity: MiniAppContinuingIdentity, systemID: UUID) {
        owner = identity.owner; localID = identity.localID; generation = identity.generation.uuidString
        registrationID = identity.registrationID.uuidString; self.systemID = systemID.uuidString
    }
    public func perform() async throws -> some IntentResult {
        guard owner == FeatureBAlarmModel.owner.rawValue,
              let generation = UUID(uuidString: generation),
              let registrationID = UUID(uuidString: registrationID),
              let systemID = UUID(uuidString: systemID) else { throw MiniAppAlarmError.staleRegistration }
        let identity = try MiniAppContinuingIdentity(owner: FeatureBAlarmModel.owner, localID: localID,
            generation: generation, registrationID: registrationID)
        try await FeatureBAlarmEnvironment.shared.service().handleSystemStop(identity: identity, systemID: systemID)
        return .result()
    }
}

public struct FeatureBAlarmIntents: AppIntentsPackage {}

@available(iOS 26.0, *)
public struct FeatureBAlarmLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeatureBAlarmMetadata>.self) { context in
            VStack(alignment: .leading) {
                Text("Feature B").font(.headline)
                Text(context.attributes.metadata?.routine ?? "B metadataなし")
                modeText(context.state.mode)
            }.activityBackgroundTint(.blue.opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { modeText(context.state.mode) }
            } compactLeading: { Text("B") }
              compactTrailing: { Image(systemName: modeSymbol(context.state.mode)) }
              minimal: { Text("B") }
        }
    }
    @ViewBuilder private func modeText(_ mode: AlarmPresentationState.Mode) -> some View {
        switch mode {
        case .alert: Text("B: 服薬時刻です")
        case .countdown: Text("B: 次回確認まで")
        case .paused: Text("B: 確認を一時停止")
        @unknown default: Text("B: 未知の状態")
        }
    }
    private func modeSymbol(_ mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .alert: "pills.fill"
        case .countdown: "timer"
        case .paused: "pause.fill"
        @unknown default: "questionmark.circle"
        }
    }
}

@available(iOS 26.0, *)
public struct FeatureBAlarmDiagnosticView: View {
    @State private var status = "B: 読み込み中"
    public init() {}
    public var body: some View {
        Form {
            Text(status).accessibilityIdentifier("alarm-feature-b.status")
            Button("OS許可を要求（app全体）") { run {
                let state = try await MiniAppAlarmKitAuthorization().request()
                status = "OS許可: \(state.rawValue)"
            } }
            Button("B: 5分後") { run { try await schedule(.fixed(.now.addingTimeInterval(300))) } }
            Button("B: 毎日21時") { run { try await schedule(.relative(hour: 21, minute: 0,
                weekdays: [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])) } }
            Button("B: 90秒timer") { run { try await schedule(.immediateCountdown(seconds: 90)) } }
            Button("B: pause") { run { try await service().perform(.pause) } }
            Button("B: resume") { run { try await service().perform(.resume) } }
            Button("B: stop") { run { try await service().perform(.stop) } }
            Button("B: cancel") { run { try await service().perform(.cancel) } }
            Button("B: cold reconcile") { run { _ = try await service().reconcile() } }
            Button("Bだけreset") { run { try service().resetFeatureOnly() } }
        }.task { refresh() }
    }
    private func service() throws -> ContinuingAlarmFeatureService<FeatureBAlarmModel> {
        try FeatureBAlarmEnvironment.shared.service()
    }
    private func schedule(_ value: ContinuingAlarmSchedule) async throws {
        _ = try await service().schedule(value) { FeatureBAlarmStopIntent(identity: $0, systemID: $1) }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); refresh() } catch { status = "B失敗: \(error)" } }
    }
    private func refresh() {
        do {
            let service = try service(), state = try service.store.read().value
            status = "\(service.status()) / \(FeatureBAlarmModel.summary(state))"
        } catch { status = "B状態失敗: \(error)" }
    }
}

@available(iOS 26.0, *)
@MainActor public enum FeatureBAlarmIntegration {
    public static func makeDefinition() throws -> MiniAppDefinition {
        let service = try FeatureBAlarmEnvironment.shared.service()
        try service.store.initialize(.initial, enabled: true)
        return MiniAppDefinition(id: FeatureBAlarmModel.owner, title: "Alarm B", systemImage: "b.square",
            backup: .init(id: FeatureBAlarmModel.owner, export: {
                let value = try service.store.read().value
                return .init(id: FeatureBAlarmModel.owner, schemaVersion: 1, payload: try JSONEncoder().encode(value))
            }, prepare: { entry in
                guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
                let value = try JSONDecoder().decode(FeatureBAlarmState.self, from: entry.payload)
                return .init { try service.store.replaceForRestore(value) }
            }),
            removal: .init(id: FeatureBAlarmModel.owner, dataDescription: "Alarm Bの業務状態") {
                try service.store.remove()
            },
            externalAccess: service.store.externalAccess(initialValue: .initial),
            continuingSurfaces: [service.surface()],
            onHostLaunch: { _ = try FeatureBAlarmEnvironment.shared.service() }
        ) { _ in FeatureBAlarmDiagnosticView() }
    }
}
#endif
