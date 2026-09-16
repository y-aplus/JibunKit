#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

public protocol MiniAppLiveActivityAttributes: ActivityAttributes, Sendable where ContentState: Sendable {
    var continuingIdentity: MiniAppContinuingIdentity { get }
}

public struct ActivityKitLiveActivityStart<Attributes: MiniAppLiveActivityAttributes>: Sendable {
    public let attributes: Attributes
    public let content: ActivityContent<Attributes.ContentState>
    public init(attributes: Attributes, content: ActivityContent<Attributes.ContentState>) {
        self.attributes = attributes; self.content = content
    }
}

public struct ActivityKitLiveActivityEnd<State: Codable & Hashable & Sendable>: Sendable {
    public let content: ActivityContent<State>?
    public let dismissalPolicy: ActivityUIDismissalPolicy
    public init(content: ActivityContent<State>?, dismissalPolicy: ActivityUIDismissalPolicy) {
        self.content = content; self.dismissalPolicy = dismissalPolicy
    }
}

private actor ActivityKitChangeTasks<Attributes: MiniAppLiveActivityAttributes> {
    private var tasks: [String: Task<Void, Never>] = [:]
    func watch(_ activity: Activity<Attributes>, continuation: AsyncStream<Void>.Continuation) {
        guard tasks[activity.id] == nil else { return }
        tasks[activity.id] = Task {
            for await _ in activity.activityStateUpdates {
                if Task.isCancelled { break }
                continuation.yield(())
            }
        }
    }
    func cancel() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
}

public struct ActivityKitLiveActivityDriver<Attributes: MiniAppLiveActivityAttributes>:
    MiniAppLiveActivityNativeDriver {
    public typealias StartInput = ActivityKitLiveActivityStart<Attributes>
    public typealias UpdateInput = ActivityContent<Attributes.ContentState>
    public typealias EndInput = ActivityKitLiveActivityEnd<Attributes.ContentState>
    private let endObservationTimeout: Duration

    public init(endObservationTimeout: Duration = .seconds(3)) {
        self.endObservationTimeout = endObservationTimeout
    }

    public func request(identity: MiniAppContinuingIdentity, input: StartInput) async throws -> String {
        guard input.attributes.continuingIdentity == identity else { throw MiniAppLiveActivityError.invalidIdentity }
        return try Activity<Attributes>.request(attributes: input.attributes, content: input.content, pushType: nil).id
    }
    public func records() async -> [MiniAppLiveActivityNativeRecord] {
        Activity<Attributes>.activities.map {
            .init(identity: $0.attributes.continuingIdentity, systemID: $0.id, state: Self.map($0.activityState))
        }
    }
    public func update(systemID: String, input: UpdateInput) async {
        guard let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) else { return }
        await activity.update(input)
    }
    public func end(systemID: String, input: EndInput) async {
        guard let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) else { return }
        await activity.end(input.content, dismissalPolicy: input.dismissalPolicy)
    }
    public func awaitEnded(systemID: String) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: endObservationTimeout)
        while clock.now < deadline {
            guard let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) else { return true }
            if [.ended, .dismissed].contains(activity.activityState) { return true }
            do { try await clock.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return false
    }
    public func changes() async -> AsyncStream<Void> {
        let watchers = ActivityKitChangeTasks<Attributes>()
        return AsyncStream { continuation in
            let discovery = Task {
                for activity in Activity<Attributes>.activities {
                    await watchers.watch(activity, continuation: continuation)
                }
                for await activity in Activity<Attributes>.activityUpdates {
                    if Task.isCancelled { break }
                    continuation.yield(())
                    await watchers.watch(activity, continuation: continuation)
                }
            }
            continuation.onTermination = { _ in
                discovery.cancel()
                Task { await watchers.cancel() }
            }
        }
    }
    private static func map(_ state: ActivityState) -> MiniAppLiveActivityNativeRecord.State {
        switch state {
        case .pending: return .pending
        case .active: return .active
        case .stale: return .stale
        case .ended: return .ended
        case .dismissed: return .dismissed
        @unknown default: return .unknown
        }
    }
}
#endif
