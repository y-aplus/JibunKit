#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureBActivityAttributes: MiniAppLiveActivityAttributes, Codable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var score: Int; public var phase: String
        public init(score: Int, phase: String) { self.score = score; self.phase = phase }
    }
    public let continuingIdentity: MiniAppContinuingIdentity
    public let matchName: String
    public init(continuingIdentity: MiniAppContinuingIdentity, matchName: String) {
        self.continuingIdentity = continuingIdentity; self.matchName = matchName
    }
}
public struct FeatureBBusinessState: Codable, Sendable {
    public var score: Int
    public static let initial = Self(score: 200)
}

public final class FeatureBLiveActivityService: @unchecked Sendable {
    public static let owner = MiniAppID("continuing-live-b")
    public static let localID = "same-id"
    private static let singletonLock = NSLock()
    nonisolated(unsafe) private static var singleton: FeatureBLiveActivityService?
    private let coordinator: MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureBActivityAttributes>>
    private let statusLock = NSLock()
    private var statusText = "B: 未開始 (200)"
    public static func shared() throws -> FeatureBLiveActivityService {
        try singletonLock.withLock {
            if let singleton { return singleton }
            let value = try FeatureBLiveActivityService(); singleton = value; return value
        }
    }
    private init() throws {
        let journal = try MiniAppContinuingJournal.shared(owner: Self.owner, namespace: "live-activity-feature-b")
        coordinator = .init(owner: Self.owner, gate: .init(), journal: .init(journal),
            native: ActivityKitLiveActivityDriver()) { identity in
                let snapshot = try MiniAppSharedState<FeatureBBusinessState>.shared(owner: Self.owner).read()
                guard identity.owner == Self.owner.rawValue, identity.localID == Self.localID,
                      identity.generation == snapshot.generation else { throw MiniAppLiveActivityError.staleIdentity }
            }
    }
    public func activate() { Task { _ = try? await coordinator.reconcile(); await coordinator.open() } }
    public func status() -> String { statusLock.withLock { statusText } }
    private func setStatus(_ value: String) { statusLock.withLock { statusText = value } }
    public func start() async throws -> MiniAppLiveActivityDescriptor {
        let snapshot = try store().read()
        let identity = try MiniAppContinuingIdentity(owner: Self.owner, localID: Self.localID, generation: snapshot.generation)
        let state = FeatureBActivityAttributes.ContentState(score: snapshot.value.score, phase: "B 継続中")
        let descriptor = try await coordinator.start(identity: identity, input: .init(
            attributes: .init(continuingIdentity: identity, matchName: "B試合"),
            content: .init(state: state, staleDate: .now.addingTimeInterval(600), relevanceScore: 80)))
        setStatus("B: started \(descriptor.systemID), score \(state.score)")
        return descriptor
    }
    public func boost(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        _ = try await coordinator.reconcile()
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID)
        let next = try await coordinator.update(descriptor) { [self] in
            let shared = try store(), snapshot = try shared.read()
            let score = try shared.update(generation: snapshot.generation) { value in value.score += 10; return value.score }
            return (score, ActivityContent(state: .init(score: score, phase: "B 更新済み"),
                                           staleDate: .now.addingTimeInterval(600), relevanceScore: 90))
        }
        setStatus("B: update requested \(next); OS display requires separate evidence")
    }
    public func end(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        _ = try await coordinator.reconcile()
        let score = try store().read().value.score
        try await coordinator.end(.init(identity: identity, systemID: systemID), input: .init(
            content: .init(state: .init(score: score, phase: "B 完了"), staleDate: nil, relevanceScore: 0),
            dismissalPolicy: .after(.now.addingTimeInterval(60))))
        setStatus("B: ended; business score retained \(score)")
    }
    public func surface() -> MiniAppContinuingSurface {
        coordinator.surface(id: "live-activity-feature-b") { _ in .init(
            content: .init(state: .init(score: 0, phase: "B 無効化"), staleDate: nil), dismissalPolicy: .immediate) }
    }
    private func store() throws -> MiniAppSharedState<FeatureBBusinessState> { try .shared(owner: Self.owner) }
}

public struct FeatureBBoostIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Bを進める"
    @Parameter(title: "Owner") public var owner: String
    @Parameter(title: "Local ID") public var localID: String
    @Parameter(title: "Generation") public var generation: String
    @Parameter(title: "Registration") public var registrationID: String
    @Parameter(title: "Activity") public var systemID: String
    public init() {}
    public init(identity: MiniAppContinuingIdentity, systemID: String) {
        owner = identity.owner; localID = identity.localID; generation = identity.generation.uuidString
        registrationID = identity.registrationID.uuidString; self.systemID = systemID
    }
    public func perform() async throws -> some IntentResult {
        guard owner == FeatureBLiveActivityService.owner.rawValue,
              let generation = UUID(uuidString: generation), let registrationID = UUID(uuidString: registrationID)
        else { throw MiniAppLiveActivityError.invalidIdentity }
        let identity = try MiniAppContinuingIdentity(owner: FeatureBLiveActivityService.owner,
            localID: localID, generation: generation, registrationID: registrationID)
        try await FeatureBLiveActivityService.shared().boost(identity: identity, systemID: systemID)
        return .result()
    }
}
public struct FeatureBIntents: AppIntentsPackage {}
public struct FeatureBLiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeatureBActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("継続表示 B・\(context.attributes.matchName)").font(.headline)
                Text("\(context.state.phase): \(context.state.score)")
                Button(intent: FeatureBBoostIntent(identity: context.attributes.continuingIdentity,
                                                   systemID: context.activityID)) { Text("Bを+10") }
            }.activityBackgroundTint(.orange.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("B") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.score)") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.phase) }
            } compactLeading: { Text("B") } compactTrailing: { Text("\(context.state.score)") } minimal: { Text("B") }
        }
    }
}
public struct FeatureBDiagnosticView: View {
    private let service: FeatureBLiveActivityService
    @State private var status: String
    @State private var descriptor: MiniAppLiveActivityDescriptor?
    public init(service: FeatureBLiveActivityService) { self.service = service; _status = State(initialValue: service.status()) }
    public var body: some View {
        VStack(spacing: 12) {
            Text(status).accessibilityIdentifier("live-b.status")
            Button("Bを開始") { run { descriptor = try await service.start() } }
            Button("Bを更新") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await service.boost(identity: descriptor.identity, systemID: descriptor.systemID) } }
            Button("Bを終了") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await service.end(identity: descriptor.identity, systemID: descriptor.systemID); self.descriptor = nil } }
        }.task { service.activate(); status = service.status() }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); status = service.status() } catch { status = "B error: \(error)" } }
    }
}

@MainActor public enum FeatureBLiveIntegration {
    public static func makeDefinition() throws -> MiniAppDefinition {
        let store = try MiniAppSharedState<FeatureBBusinessState>.shared(owner: FeatureBLiveActivityService.owner)
        let service = try FeatureBLiveActivityService.shared()
        let backup = MiniAppBackupProvider(id: FeatureBLiveActivityService.owner, export: {
            .init(id: FeatureBLiveActivityService.owner, schemaVersion: 1,
                  payload: try JSONEncoder().encode(store.read().value))
        }, prepare: { entry in
            guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
            let value = try JSONDecoder().decode(FeatureBBusinessState.self, from: entry.payload)
            return .init { try store.replaceForRestore(value) }
        })
        return MiniAppDefinition(id: FeatureBLiveActivityService.owner, title: "継続表示 B", systemImage: "b.square",
            backup: backup,
            removal: .init(id: FeatureBLiveActivityService.owner, dataDescription: "継続表示Bの業務状態") { try store.remove() },
            externalAccess: store.externalAccess(initialValue: .initial), continuingSurfaces: [service.surface()],
            onHostLaunch: { service.activate() }) { _ in FeatureBDiagnosticView(service: service) }
    }
}
#endif
