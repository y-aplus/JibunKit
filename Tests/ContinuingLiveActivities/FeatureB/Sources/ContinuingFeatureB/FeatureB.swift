#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureBActivityAttributes: MiniAppLiveActivityAttributes, Codable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var score: Int
        public var phase: String
        public init(score: Int, phase: String) { self.score = score; self.phase = phase }
    }
    public let continuingIdentity: MiniAppContinuingIdentity
    public init(continuingIdentity: MiniAppContinuingIdentity) { self.continuingIdentity = continuingIdentity }
}

public struct FeatureBBusinessState: Codable, Sendable {
    public var score: Int
    public static let initial = Self(score: 200)
}

public actor FeatureBLiveActivityService {
    public static let shared = FeatureBLiveActivityService()
    public nonisolated static let owner = MiniAppID("continuing-live-b")
    public nonisolated static let localID = "same-id"
    private var coordinator: MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureBActivityAttributes>>?
    private var lastResult = "B: 未開始 (200)"
    public func status() -> String { lastResult }

    public func start() async throws -> MiniAppLiveActivityDescriptor<FeatureBActivityAttributes.ContentState> {
        let snapshot = try store().read()
        let identity = try MiniAppContinuingIdentity(owner: Self.owner, localID: Self.localID,
                                                      generation: snapshot.generation)
        let content = FeatureBActivityAttributes.ContentState(score: snapshot.value.score, phase: "B 継続中")
        let descriptor = try await service().start(identity: identity, content: content)
        lastResult = "B: started \(descriptor.systemID), score \(content.score)"
        return descriptor
    }

    public func boost(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        let shared = try store(), snapshot = try shared.read()
        guard snapshot.generation == identity.generation else { throw MiniAppLiveActivityError.staleIdentity }
        let next = try shared.update(generation: snapshot.generation) { value in value.score += 10; return value.score }
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID,
            content: FeatureBActivityAttributes.ContentState(score: snapshot.value.score, phase: "B 継続中"))
        _ = try await service().update(descriptor, content: .init(score: next, phase: "B 更新済み"))
        lastResult = "B: updated \(next)"
    }

    public func end(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        let score = try store().read().value.score
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID,
            content: FeatureBActivityAttributes.ContentState(score: score, phase: "B 継続中"))
        try await service().end(descriptor, finalContent: .init(score: score, phase: "B 完了"), immediately: true)
        lastResult = "B: ended; business score retained \(score)"
    }

    public func surface() throws -> MiniAppContinuingSurface {
        service().surface(id: "live-activity") { _ in .init(score: 0, phase: "B 無効化") }
    }
    private func store() throws -> MiniAppSharedState<FeatureBBusinessState> { try .shared(owner: Self.owner) }
    private func service() throws -> MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureBActivityAttributes>> {
        if let coordinator { return coordinator }
        let journal = try MiniAppContinuingJournal.shared(owner: Self.owner, namespace: "live-activity")
        let value = MiniAppLiveActivityCoordinator(owner: Self.owner, gate: .init(), journal: .init(journal),
            native: ActivityKitLiveActivityDriver()) { identity in
                let snapshot = try MiniAppSharedState<FeatureBBusinessState>.shared(owner: Self.owner).read()
                guard identity.owner == Self.owner.rawValue, identity.localID == Self.localID,
                      identity.generation == snapshot.generation else { throw MiniAppLiveActivityError.staleIdentity }
            }
        coordinator = value
        return value
    }
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
              let generation = UUID(uuidString: generation), let registrationID = UUID(uuidString: registrationID) else {
            throw MiniAppLiveActivityError.invalidIdentity
        }
        let identity = try MiniAppContinuingIdentity(owner: FeatureBLiveActivityService.owner,
            localID: localID, generation: generation, registrationID: registrationID)
        try await FeatureBLiveActivityService.shared.boost(identity: identity, systemID: systemID)
        return .result()
    }
}
public struct FeatureBIntents: AppIntentsPackage {}

public struct FeatureBLiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeatureBActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("継続表示 B").font(.headline)
                Text("\(context.state.phase): \(context.state.score)")
                Button(intent: FeatureBBoostIntent(identity: context.attributes.continuingIdentity,
                                                   systemID: context.activityID)) { Text("Bを+10") }
            }.activityBackgroundTint(.orange.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("B") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.score)") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.phase) }
            } compactLeading: { Text("B") } compactTrailing: { Text("\(context.state.score)") }
              minimal: { Text("B") }
        }
    }
}

public struct FeatureBDiagnosticView: View {
    @State private var status = "B: 読み込み中"
    @State private var descriptor: MiniAppLiveActivityDescriptor<FeatureBActivityAttributes.ContentState>?
    public init() {}
    public var body: some View {
        VStack(spacing: 12) {
            Text(status).accessibilityIdentifier("live-b.status")
            Button("Bを開始") { run { descriptor = try await FeatureBLiveActivityService.shared.start() } }
            Button("Bを更新") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await FeatureBLiveActivityService.shared.boost(identity: descriptor.identity, systemID: descriptor.systemID) } }
            Button("Bを終了") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await FeatureBLiveActivityService.shared.end(identity: descriptor.identity, systemID: descriptor.systemID); self.descriptor = nil } }
        }.task {
            do { try MiniAppSharedState<FeatureBBusinessState>.shared(owner: FeatureBLiveActivityService.owner).initialize(.initial, enabled: true) }
            catch { status = "B setup error: \(error)" }
            refresh()
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); refresh() } catch { status = "B error: \(error)" } }
    }
    private func refresh() { Task { status = await FeatureBLiveActivityService.shared.status() } }
}
#endif
