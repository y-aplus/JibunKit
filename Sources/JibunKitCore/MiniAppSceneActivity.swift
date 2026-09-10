import Foundation

/// One Feature's selection and activity in one mounted host scene connection.
/// Selection is independent of foreground activity and never implies task cancellation.
public struct MiniAppSceneActivity: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case active, inactive, background }

    public let featureID: MiniAppID
    public let sceneID: UUID
    /// nil ends this scene connection. A later connection has a new sceneID.
    public let phase: Phase?
    public let isSelected: Bool
    public var isConnected: Bool { phase != nil }
}

/// A host owns one dispatcher per scene, separate from aggregate host activity.
/// Delivers to integrations even before their root views have been constructed.
@MainActor
public final class MiniAppSceneActivityDispatcher {
    public typealias Handler = @MainActor (MiniAppSceneActivity) -> Void
    private struct Snapshot: Equatable {
        let id: UUID
        let phase: MiniAppSceneActivity.Phase?
        let selectedID: MiniAppID?
    }
    private let handlers: [(MiniAppID, Handler)]
    private var requested: Snapshot?
    private var pending: [Snapshot] = []
    private var delivered: [MiniAppID: MiniAppSceneActivity] = [:]
    private var delivering = false

    public init(handlers: [(MiniAppID, Handler)]) {
        precondition(handlers.allSatisfy { $0.0.isValid })
        precondition(Set(handlers.map { $0.0 }).count == handlers.count)
        self.handlers = handlers
    }

    public func connect(phase: MiniAppSceneActivity.Phase, selectedID: MiniAppID?) {
        if requested?.phase != nil {
            update(phase: phase, selectedID: selectedID)
        } else {
            enqueue(Snapshot(id: UUID(), phase: phase, selectedID: selectedID))
        }
    }

    /// Updates received while disconnected are ignored; only connect starts a lifetime.
    public func update(phase: MiniAppSceneActivity.Phase, selectedID: MiniAppID?) {
        guard let requested, requested.phase != nil else { return }
        enqueue(Snapshot(id: requested.id, phase: phase, selectedID: selectedID))
    }

    public func disconnect() {
        guard let requested, requested.phase != nil else { return }
        enqueue(Snapshot(id: requested.id, phase: nil, selectedID: nil))
    }

    private func enqueue(_ snapshot: Snapshot) {
        guard snapshot != requested else { return }
        requested = snapshot
        pending.append(snapshot)
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            // Finish this transition for all owners before a reentrant transition.
            for (id, handler) in handlers {
                let activity = MiniAppSceneActivity(
                    featureID: id, sceneID: next.id, phase: next.phase,
                    isSelected: next.selectedID == id
                )
                guard delivered[id] != activity else { continue }
                delivered[id] = activity
                handler(activity)
            }
        }
    }
}
