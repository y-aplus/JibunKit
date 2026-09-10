import Foundation

/// An opt-in screen-awake request which is effective only while this Feature
/// is selected in at least one active scene connection. Other requests survive.
@MainActor
public final class MiniAppSceneIdleTimer {
    public enum Failure: Error { case closed }
    public let owner: MiniAppID
    private let timer: MiniAppIdleTimer
    private var activeScenes: Set<UUID> = []
    private var requested = false
    private var closed = false
    private var lease: MiniAppIdleTimerLease?
    private var reconciling = false

    public init(owner: MiniAppID, timer: MiniAppIdleTimer) {
        precondition(owner.isValid)
        self.owner = owner
        self.timer = timer
    }

    /// Retains the operation's intent across deselection/background transitions.
    /// Call false when the operation finishes, even if its screen is hidden.
    public func setRequested(_ value: Bool) throws {
        guard !closed else { throw Failure.closed }
        requested = value
        reconcile()
    }

    /// Forward this Feature's onSceneActivityChange callback. Never accepts
    /// another Feature's event, and never reopens after runtime shutdown.
    public func receive(_ activity: MiniAppSceneActivity) {
        guard !closed, activity.featureID == owner else { return }
        if activity.isSelected && activity.phase == .active {
            activeScenes.insert(activity.sceneID)
        } else {
            activeScenes.remove(activity.sceneID)
        }
        reconcile()
    }

    /// Terminal, synchronous cleanup; subsequent activity cannot reacquire a lease.
    public func close() {
        closed = true
        requested = false
        activeScenes.removeAll()
        reconcile()
    }

    private func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        // apply callbacks can reenter and change intent during acquire/release.
        while true {
            if requested && !activeScenes.isEmpty {
                guard lease == nil else { return }
                lease = timer.preventSleep(for: owner)
            } else {
                guard let current = lease else { return }
                lease = nil
                current.release()
            }
        }
    }
}

public extension MiniAppRuntime {
    /// Connect activity delivery before accepting screen-awake operations.
    /// Construct this scope with the runtime, not only when a root View appears.
    func makeSceneIdleTimer(for owner: MiniAppID, using timer: MiniAppIdleTimer) throws -> MiniAppSceneIdleTimer {
        let scope = MiniAppSceneIdleTimer(owner: owner, timer: timer)
        try onShutdown { scope.close() }
        return scope
    }
}
