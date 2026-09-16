#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Feature-owned attributes expose the complete immutable routing identity.
/// ContentState meaning remains entirely in the Feature type.
public protocol MiniAppLiveActivityAttributes: ActivityAttributes, Sendable
where ContentState: Sendable {
    var continuingIdentity: MiniAppContinuingIdentity { get }
    init(continuingIdentity: MiniAppContinuingIdentity)
}

public struct ActivityKitLiveActivityDriver<Attributes: MiniAppLiveActivityAttributes>: MiniAppLiveActivityNativeDriver {
    public typealias Content = Attributes.ContentState
    private let observationTimeout: Duration

    public init(observationTimeout: Duration = .seconds(3)) {
        self.observationTimeout = observationTimeout
    }

    public func request(identity: MiniAppContinuingIdentity, content: Content) async throws -> String {
        let activity = try Activity<Attributes>.request(
            attributes: Attributes(continuingIdentity: identity),
            content: ActivityContent(state: content, staleDate: nil), pushType: nil)
        return activity.id
    }

    public func records() async -> [MiniAppLiveActivityNativeRecord] {
        Activity<Attributes>.activities.map { activity in
            .init(identity: activity.attributes.continuingIdentity, systemID: activity.id,
                  state: Self.map(activity.activityState))
        }
    }

    public func update(systemID: String, content: Content) async {
        guard let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) else { return }
        await activity.update(ActivityContent(state: content, staleDate: nil))
    }

    public func end(systemID: String, finalContent: Content, immediately: Bool) async {
        guard let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) else { return }
        await activity.end(ActivityContent(state: finalContent, staleDate: nil),
                           dismissalPolicy: immediately ? .immediate : .default)
    }

    public func awaitState(systemID: String,
        accepted: Set<MiniAppLiveActivityNativeRecord.State>) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: observationTimeout)
        while clock.now < deadline {
            if let activity = Activity<Attributes>.activities.first(where: { $0.id == systemID }) {
                if accepted.contains(Self.map(activity.activityState)) { return true }
            } else if accepted.contains(.dismissed) { return true }
            do { try await clock.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return false
    }

    private static func map(_ state: ActivityState) -> MiniAppLiveActivityNativeRecord.State {
        switch state {
        case .active, .pending: return .active
        case .stale: return .stale
        case .ended: return .ended
        case .dismissed: return .dismissed
        @unknown default: return .ended
        }
    }
}
#endif
