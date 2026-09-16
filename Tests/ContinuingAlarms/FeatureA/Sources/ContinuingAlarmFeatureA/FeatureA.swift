#if os(iOS)
import ActivityKit
import AlarmKit
import AppIntents
import ContinuingAlarmSupport
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureAAlarmMetadata: AlarmMetadata {
    public let owner: String
    public let localID: String
    public let generation: UUID
    public let registrationID: UUID
    public let reason: String
}

public struct FeatureAAlarmState: Codable, Sendable {
    public var stopEvents: Int
    public var label: String
    public static let initial = Self(stopEvents: 0, label: "集中セッション")
}

public enum FeatureAAlarmModel: ContinuingAlarmFixtureFeature {
    public static let owner = MiniAppID("alarm-feature-a")
    public static let localID = "same-id"
    public static let title: LocalizedStringResource = "A: 集中を終える"
    public static let tint = Color.orange
    public static let initialState = FeatureAAlarmState.initial
    public static func metadata(identity: MiniAppContinuingIdentity) -> FeatureAAlarmMetadata {
        .init(owner: identity.owner, localID: identity.localID, generation: identity.generation,
              registrationID: identity.registrationID, reason: "集中セッション")
    }
    public static func summary(_ state: FeatureAAlarmState) -> String {
        "\(state.label) / stop callback \(state.stopEvents)"
    }
    public static func recordSystemStop(_ state: inout FeatureAAlarmState) { state.stopEvents += 1 }
}

@available(iOS 26.0, *)
public final class FeatureAAlarmEnvironment: @unchecked Sendable {
    public static let shared = FeatureAAlarmEnvironment()
    private let lock = NSLock()
    private var cached: ContinuingAlarmFeatureService<FeatureAAlarmModel>?
    private init() {}

    public func service() throws -> ContinuingAlarmFeatureService<FeatureAAlarmModel> {
        try lock.withLock {
            if let cached { return cached }
            let store = try MiniAppSharedState<FeatureAAlarmState>.shared(owner: FeatureAAlarmModel.owner)
            let journal = try MiniAppContinuingJournal.shared(owner: FeatureAAlarmModel.owner, namespace: "alarmkit")
            let value = ContinuingAlarmFeatureService<FeatureAAlarmModel>(store: store, journal: journal)
            cached = value
            return value
        }
    }
}

@available(iOS 26.0, *)
public struct FeatureAAlarmStopIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Aの停止を記録"
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
        guard owner == FeatureAAlarmModel.owner.rawValue,
              let generation = UUID(uuidString: generation),
              let registrationID = UUID(uuidString: registrationID),
              let systemID = UUID(uuidString: systemID) else { throw MiniAppAlarmError.staleRegistration }
        let identity = try MiniAppContinuingIdentity(owner: FeatureAAlarmModel.owner, localID: localID,
            generation: generation, registrationID: registrationID)
        try await FeatureAAlarmEnvironment.shared.service().handleSystemStop(identity: identity, systemID: systemID)
        return .result()
    }
}

public struct FeatureAAlarmIntents: AppIntentsPackage {}

@available(iOS 26.0, *)
public struct FeatureAAlarmLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeatureAAlarmMetadata>.self) { context in
            VStack(alignment: .leading) {
                Text("Feature A").font(.headline)
                Text(context.attributes.metadata?.reason ?? "A metadataなし")
                modeText(context.state.mode)
            }.activityBackgroundTint(.orange.opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { modeText(context.state.mode) }
            } compactLeading: { Text("A") }
              compactTrailing: { Image(systemName: modeSymbol(context.state.mode)) }
              minimal: { Text("A") }
        }
    }
    @ViewBuilder private func modeText(_ mode: AlarmPresentationState.Mode) -> some View {
        switch mode {
        case .alert: Text("A: 時間です")
        case .countdown: Text("A: カウントダウン中")
        case .paused: Text("A: 一時停止中")
        @unknown default: Text("A: 未知の状態")
        }
    }
    private func modeSymbol(_ mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .alert: "bell.fill"
        case .countdown: "timer"
        case .paused: "pause.fill"
        @unknown default: "questionmark.circle"
        }
    }
}

@available(iOS 26.0, *)
public struct FeatureAAlarmDiagnosticView: View {
    @State private var status = "A: 読み込み中"
    public init() {}
    public var body: some View {
        Form {
            Text(status).accessibilityIdentifier("alarm-feature-a.status")
            Button("OS許可を要求（app全体）") { run {
                let state = try await MiniAppAlarmKitAuthorization().request()
                status = "OS許可: \(state.rawValue)"
            } }
            Button("A: 5分後") { run { try await schedule(.fixed(.now.addingTimeInterval(300))) } }
            Button("A: 平日9時") { run { try await schedule(.relative(hour: 9, minute: 0,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])) } }
            Button("A: 60秒timer") { run { try await schedule(.immediateCountdown(seconds: 60)) } }
            Button("A: pause") { run { try await service().perform(.pause) } }
            Button("A: resume") { run { try await service().perform(.resume) } }
            Button("A: stop") { run { try await service().perform(.stop) } }
            Button("A: cancel") { run { try await service().perform(.cancel) } }
            Button("A: cold reconcile") { run { _ = try await service().reconcile() } }
            Button("Aだけreset") { run { try service().resetFeatureOnly() } }
        }.task { refresh() }
    }
    private func service() throws -> ContinuingAlarmFeatureService<FeatureAAlarmModel> {
        try FeatureAAlarmEnvironment.shared.service()
    }
    private func schedule(_ value: ContinuingAlarmSchedule) async throws {
        _ = try await service().schedule(value) { FeatureAAlarmStopIntent(identity: $0, systemID: $1) }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); refresh() } catch { status = "A失敗: \(error)" } }
    }
    private func refresh() {
        do {
            let service = try service(), state = try service.store.read().value
            status = "\(service.status()) / \(FeatureAAlarmModel.summary(state))"
        } catch { status = "A状態失敗: \(error)" }
    }
}

@available(iOS 26.0, *)
@MainActor public enum FeatureAAlarmIntegration {
    public static func makeDefinition() throws -> MiniAppDefinition {
        let service = try FeatureAAlarmEnvironment.shared.service()
        try service.store.initialize(.initial, enabled: true)
        return MiniAppDefinition(id: FeatureAAlarmModel.owner, title: "Alarm A", systemImage: "a.square",
            backup: .init(id: FeatureAAlarmModel.owner, export: {
                let value = try service.store.read().value
                return .init(id: FeatureAAlarmModel.owner, schemaVersion: 1, payload: try JSONEncoder().encode(value))
            }, prepare: { entry in
                guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
                let value = try JSONDecoder().decode(FeatureAAlarmState.self, from: entry.payload)
                return .init { try service.store.replaceForRestore(value) }
            }),
            removal: .init(id: FeatureAAlarmModel.owner, dataDescription: "Alarm Aの業務状態") {
                try service.store.remove()
            },
            externalAccess: service.store.externalAccess(initialValue: .initial),
            continuingSurfaces: [service.surface()],
            onHostLaunch: { _ = try FeatureAAlarmEnvironment.shared.service() }
        ) { _ in FeatureAAlarmDiagnosticView() }
    }
}
#endif
