#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureAActivityAttributes: MiniAppLiveActivityAttributes, Codable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var count: Int
        public var message: String
        public init(count: Int, message: String) { self.count = count; self.message = message }
    }
    public let continuingIdentity: MiniAppContinuingIdentity
    public init(continuingIdentity: MiniAppContinuingIdentity) { self.continuingIdentity = continuingIdentity }
}

public struct FeatureABusinessState: Codable, Sendable {
    public var count: Int
    public static let initial = Self(count: 10)
}

public actor FeatureALiveActivityService {
    public static let shared = FeatureALiveActivityService()
    public nonisolated static let owner = MiniAppID("continuing-live-a")
    public nonisolated static let localID = "same-id"
    private var coordinator: MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureAActivityAttributes>>?
    private var lastResult = "A: 未開始 (10)"

    public func status() -> String { lastResult }

    public func start() async throws -> MiniAppLiveActivityDescriptor<FeatureAActivityAttributes.ContentState> {
        let store = try businessStore()
        let snapshot = try store.read()
        let identity = try MiniAppContinuingIdentity(owner: Self.owner, localID: Self.localID,
                                                      generation: snapshot.generation)
        let content = FeatureAActivityAttributes.ContentState(count: snapshot.value.count, message: "A 実行中")
        let descriptor = try await service().start(identity: identity, content: content)
        lastResult = "A: started \(descriptor.systemID), count \(content.count)"
        return descriptor
    }

    public func advance(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        let store = try businessStore()
        let snapshot = try store.read()
        guard snapshot.generation == identity.generation else { throw MiniAppLiveActivityError.staleIdentity }
        let next = try store.update(generation: snapshot.generation) { value in value.count += 1; return value.count }
        let old = FeatureAActivityAttributes.ContentState(count: snapshot.value.count, message: "A 実行中")
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID, content: old)
        _ = try await service().update(descriptor, content: .init(count: next, message: "A 更新済み"))
        lastResult = "A: updated \(next)"
    }

    public func end(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        let count = try businessStore().read().value.count
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID,
            content: FeatureAActivityAttributes.ContentState(count: count, message: "A 実行中"))
        try await service().end(descriptor, finalContent: .init(count: count, message: "A 完了"), immediately: true)
        lastResult = "A: ended; business count retained \(count)"
    }

    public func resetAOnly() throws {
        let shared = try businessStore(), snapshot = try shared.read()
        try shared.update(generation: snapshot.generation) { $0 = .initial }
        lastResult = "A: reset; B untouched"
    }

    public func surface() throws -> MiniAppContinuingSurface {
        service().surface(id: "live-activity") { _ in .init(count: 0, message: "A 無効化") }
    }

    private func businessStore() throws -> MiniAppSharedState<FeatureABusinessState> {
        try .shared(owner: Self.owner)
    }

    private func service() throws -> MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureAActivityAttributes>> {
        if let coordinator { return coordinator }
        let journal = try MiniAppContinuingJournal.shared(owner: Self.owner, namespace: "live-activity")
        let value = MiniAppLiveActivityCoordinator(owner: Self.owner, gate: .init(), journal: .init(journal),
            native: ActivityKitLiveActivityDriver()) { identity in
                let snapshot = try MiniAppSharedState<FeatureABusinessState>.shared(owner: Self.owner).read()
                guard identity.owner == Self.owner.rawValue, identity.localID == Self.localID,
                      identity.generation == snapshot.generation else { throw MiniAppLiveActivityError.staleIdentity }
            }
        coordinator = value
        return value
    }
}

public struct FeatureAAdvanceIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Aを進める"
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
        guard owner == FeatureALiveActivityService.owner.rawValue,
              let generation = UUID(uuidString: generation), let registrationID = UUID(uuidString: registrationID) else {
            throw MiniAppLiveActivityError.invalidIdentity
        }
        let identity = try MiniAppContinuingIdentity(owner: FeatureALiveActivityService.owner,
            localID: localID, generation: generation, registrationID: registrationID)
        try await FeatureALiveActivityService.shared.advance(identity: identity, systemID: systemID)
        return .result()
    }
}

public struct FeatureAIntents: AppIntentsPackage {}

public struct FeatureALiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeatureAActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("継続表示 A").font(.headline)
                Text("\(context.state.message): \(context.state.count)")
                Button(intent: FeatureAAdvanceIntent(identity: context.attributes.continuingIdentity,
                                                     systemID: context.activityID)) { Text("Aを+1") }
            }.activityBackgroundTint(.blue.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("A") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.count)") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.message) }
            } compactLeading: { Text("A") } compactTrailing: { Text("\(context.state.count)") }
              minimal: { Text("A") }
        }
    }
}

public struct FeatureADiagnosticView: View {
    @State private var status = "A: 読み込み中"
    @State private var descriptor: MiniAppLiveActivityDescriptor<FeatureAActivityAttributes.ContentState>?
    public init() {}
    public var body: some View {
        VStack(spacing: 12) {
            Text(status).accessibilityIdentifier("live-a.status")
            Button("Aを開始") { run { descriptor = try await FeatureALiveActivityService.shared.start() } }
            Button("Aを更新") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await FeatureALiveActivityService.shared.advance(identity: descriptor.identity, systemID: descriptor.systemID) } }
            Button("Aを終了") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await FeatureALiveActivityService.shared.end(identity: descriptor.identity, systemID: descriptor.systemID); self.descriptor = nil } }
            Button("Aだけreset") { run { try await FeatureALiveActivityService.shared.resetAOnly() } }
        }.task {
            do { try MiniAppSharedState<FeatureABusinessState>.shared(owner: FeatureALiveActivityService.owner).initialize(.initial, enabled: true) }
            catch { status = "A setup error: \(error)" }
            refresh()
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); refresh() } catch { status = "A error: \(error)" } }
    }
    private func refresh() { Task { status = await FeatureALiveActivityService.shared.status() } }
}
#endif
