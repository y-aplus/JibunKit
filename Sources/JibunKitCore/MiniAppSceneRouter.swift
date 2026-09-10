import Foundation

/// Chooses one registered scene for process-level navigation requests. Each
/// scene retains its own navigation state; this registry never owns its path.
@MainActor
public final class MiniAppSceneRouter {
    private struct Scene {
        var isActive: Bool
        let open: @MainActor (MiniAppRoute?) -> Void
    }
    private var scenes: [UUID: Scene] = [:]
    private var order: [UUID] = []
    private var pending: [MiniAppRoute?] = []
    private var delivering = false

    public init() {}

    /// The returned registration is tied to this mounted scene instance.
    @discardableResult
    public func register(isActive: Bool, open: @escaping @MainActor (MiniAppRoute?) -> Void) -> UUID {
        let id = UUID()
        scenes[id] = Scene(isActive: isActive, open: open)
        order.append(id)
        drain()
        return id
    }

    public func update(_ id: UUID, isActive: Bool) {
        guard var scene = scenes[id], scene.isActive != isActive else { return }
        scene.isActive = isActive
        scenes[id] = scene
        if isActive {
            order.removeAll { $0 == id }
            order.append(id)
        }
        drain()
    }

    public func unregister(_ id: UUID) {
        scenes[id] = nil
        order.removeAll { $0 == id }
    }

    /// nil explicitly requests the app list. Before any scene exists, retain
    /// only the latest requested location. Reentrant requests deliver afterwards.
    public func open(_ route: MiniAppRoute?) {
        pending = [route]
        drain()
    }

    private func drain() {
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        while !pending.isEmpty {
            // Prefer the most recently activated scene, then the most recently
            // registered/activated surviving scene. Never broadcast navigation.
            let id = order.reversed().first { scenes[$0]?.isActive == true } ?? order.last
            guard let id, let scene = scenes[id] else { return }
            let route = pending.removeFirst()
            scene.open(route)
        }
    }
}
