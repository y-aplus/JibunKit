#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureAActivityAttributes: MiniAppLiveActivityAttributes, Codable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var count: Int; public var message: String
        public init(count: Int, message: String) { self.count = count; self.message = message }
    }
    public let continuingIdentity: MiniAppContinuingIdentity
    public let orderName: String
    public init(continuingIdentity: MiniAppContinuingIdentity, orderName: String) {
        self.continuingIdentity = continuingIdentity; self.orderName = orderName
    }
}

public struct FeatureABusinessState: Codable, Sendable {
    public var count: Int
    public static let initial = Self(count: 10)
}

public final class FeatureALiveActivityService: @unchecked Sendable {
    public static let owner = MiniAppID("continuing-live-a")
    public static let localID = "same-id"
    private static let singletonLock = NSLock()
    nonisolated(unsafe) private static var singleton: FeatureALiveActivityService?
    private let coordinator: MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<FeatureAActivityAttributes>>
    private let statusLock = NSLock()
    private var statusText = "A: 未開始 (10)"

    public static func shared() throws -> FeatureALiveActivityService {
        try singletonLock.withLock {
            if let singleton { return singleton }
            let value = try FeatureALiveActivityService(); singleton = value; return value
        }
    }
    private init() throws {
        let journal = try MiniAppContinuingJournal.shared(owner: Self.owner, namespace: "live-activity-feature-a")
        coordinator = .init(owner: Self.owner, gate: .init(), journal: .init(journal),
            native: ActivityKitLiveActivityDriver()) { identity in
                let snapshot = try MiniAppSharedState<FeatureABusinessState>.shared(owner: Self.owner).read()
                guard identity.owner == Self.owner.rawValue, identity.localID == Self.localID,
                      identity.generation == snapshot.generation else { throw MiniAppLiveActivityError.staleIdentity }
            }
    }

    public func activate() async throws {
        _ = try store().read()
        _ = try await coordinator.reconcile()
        try await coordinator.observe()
    }
    public func activateAfterLaunch() {
        Task {
            do { try await activate() }
            catch { setStatus("A: reconcile error: \(error)") }
        }
    }
    public func currentDescriptor() async throws -> MiniAppLiveActivityDescriptor? {
        _ = try await coordinator.reconcile()
        let snapshot = try store().read()
        let current = try await coordinator.current(localID: Self.localID, generation: snapshot.generation)
        setStatus("A: count \(snapshot.value.count); activity \(current?.systemID ?? "none")")
        return current
    }
    public func status() -> String { statusLock.withLock { statusText } }
    private func setStatus(_ value: String) { statusLock.withLock { statusText = value } }

    public func start() async throws -> MiniAppLiveActivityDescriptor {
        let snapshot = try store().read()
        let identity = try MiniAppContinuingIdentity(owner: Self.owner, localID: Self.localID,
                                                      generation: snapshot.generation)
        let state = FeatureAActivityAttributes.ContentState(count: snapshot.value.count, message: "A 実行中")
        let descriptor = try await coordinator.start(identity: identity, input: .init(
            attributes: .init(continuingIdentity: identity, orderName: "A注文"),
            content: .init(state: state, staleDate: .now.addingTimeInterval(900), relevanceScore: 50)))
        setStatus("A: started \(descriptor.systemID), count \(state.count)")
        return descriptor
    }

    public func advance(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        _ = try await coordinator.reconcile()
        let descriptor = MiniAppLiveActivityDescriptor(identity: identity, systemID: systemID)
        let next = try await coordinator.update(descriptor) { [self] in
            let shared = try store()
            let count = try shared.update(generation: identity.generation) { value in
                let (next, overflow) = value.count.addingReportingOverflow(1)
                guard !overflow else { throw MiniAppBackupError.invalidEntry }
                value.count = next
                return next
            }
            return (count, ActivityContent(state: .init(count: count, message: "A 更新済み"),
                                           staleDate: .now.addingTimeInterval(900), relevanceScore: 60))
        }
        setStatus("A: update requested \(next); OS display requires separate evidence")
    }

    public func end(identity: MiniAppContinuingIdentity, systemID: String) async throws {
        _ = try await coordinator.reconcile()
        let count = try store().read().value.count
        try await coordinator.end(.init(identity: identity, systemID: systemID), input: .init(
            content: .init(state: .init(count: count, message: "A 完了"), staleDate: nil, relevanceScore: 0),
            dismissalPolicy: .immediate))
        setStatus("A: ended; business count retained \(count)")
    }

    public func resetAOnly() throws {
        let shared = try store(), snapshot = try shared.read()
        try shared.update(generation: snapshot.generation) { $0 = .initial }
        setStatus("A: reset; B untouched")
    }
    public func surface() -> MiniAppContinuingSurface {
        coordinator.surface(id: "live-activity-feature-a") { _ in .init(
            content: .init(state: .init(count: 0, message: "A 無効化"), staleDate: nil),
            dismissalPolicy: .immediate) }
    }
    private func store() throws -> MiniAppSharedState<FeatureABusinessState> { try .shared(owner: Self.owner) }
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
              let generation = UUID(uuidString: generation), let registrationID = UUID(uuidString: registrationID)
        else { throw MiniAppLiveActivityError.invalidIdentity }
        let identity = try MiniAppContinuingIdentity(owner: FeatureALiveActivityService.owner,
            localID: localID, generation: generation, registrationID: registrationID)
        try await FeatureALiveActivityService.shared().advance(identity: identity, systemID: systemID)
        return .result()
    }
}
public struct FeatureAIntents: AppIntentsPackage {}

public struct FeatureALiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeatureAActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("継続表示 A・\(context.attributes.orderName)").font(.headline)
                Text("\(context.state.message): \(context.state.count)")
                Button(intent: FeatureAAdvanceIntent(identity: context.attributes.continuingIdentity,
                                                     systemID: context.activityID)) { Text("Aを+1") }
            }.activityBackgroundTint(.blue.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("A") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.count)") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.message) }
            } compactLeading: { Text("A") } compactTrailing: { Text("\(context.state.count)") } minimal: { Text("A") }
        }
    }
}

public struct FeatureADiagnosticView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let service: FeatureALiveActivityService
    @State private var status: String
    @State private var descriptor: MiniAppLiveActivityDescriptor?
    public init(service: FeatureALiveActivityService) { self.service = service; _status = State(initialValue: service.status()) }
    public var body: some View {
        VStack(spacing: 12) {
            Text(status).accessibilityIdentifier("live-a.status")
            Button("Aを開始") { run { descriptor = try await service.start() } }
            Button("Aを更新") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await service.advance(identity: descriptor.identity, systemID: descriptor.systemID) } }
            Button("Aを終了") { run { guard let descriptor else { throw MiniAppLiveActivityError.missingRegistration }; try await service.end(identity: descriptor.identity, systemID: descriptor.systemID); self.descriptor = nil } }
            Button("Aだけreset") { run { try service.resetAOnly() } }
        }.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            do {
                try await service.activate()
                descriptor = try await service.currentDescriptor()
                status = service.status()
            } catch is CancellationError {
                return
            } catch { status = "A error: \(error)" }
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); status = service.status() } catch { status = "A error: \(error)" } }
    }
}

@MainActor public enum FeatureALiveIntegration {
    public static func makeDefinition() throws -> MiniAppDefinition {
        let store = try MiniAppSharedState<FeatureABusinessState>.shared(owner: FeatureALiveActivityService.owner)
        let service = try FeatureALiveActivityService.shared()
        let backup = MiniAppBackupProvider(id: FeatureALiveActivityService.owner, export: {
            .init(id: FeatureALiveActivityService.owner, schemaVersion: 1,
                  payload: try JSONEncoder().encode(store.read().value))
        }, prepare: { entry in
            guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
            let value = try JSONDecoder().decode(FeatureABusinessState.self, from: entry.payload)
            return .init { try store.replaceForRestore(value) }
        })
        return MiniAppDefinition(id: FeatureALiveActivityService.owner, title: "継続表示 A", systemImage: "a.square",
            backup: backup,
            removal: .init(id: FeatureALiveActivityService.owner, dataDescription: "継続表示Aの業務状態") { try store.remove() },
            externalAccess: store.externalAccess(initialValue: .initial), continuingSurfaces: [service.surface()],
            onHostLaunch: { service.activateAfterLaunch() }) { _ in FeatureADiagnosticView(service: service) }
    }
}
#endif
