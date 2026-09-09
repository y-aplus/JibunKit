import Foundation

/// A cooperative lifetime for Feature work and its resources. Construct a new
/// runtime when restarting; a shut-down runtime never accepts new work.
@MainActor
public final class MiniAppRuntime {
    public enum Failure: Error { case closed }
    public private(set) var isClosed = false
    private let tasks = MiniAppTaskScope()
    private var cleanups: [@MainActor @Sendable () -> Void] = []
    private var shutdownTask: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func start(_ operation: @escaping @Sendable () async -> Void) throws -> Task<Void, Never> {
        guard !isClosed else { throw Failure.closed }
        return tasks.start(operation)
    }

    /// Register resource cleanup before starting work which uses that resource.
    /// Runs in reverse registration order, after owned tasks finish.
    public func onShutdown(_ cleanup: @escaping @MainActor @Sendable () -> Void) throws {
        guard !isClosed else { throw Failure.closed }
        cleanups.append(cleanup)
    }

    public func cancelTasks() { tasks.cancelAll() }

    /// Call from an external coordinator, not from a task owned by this runtime.
    /// Concurrent callers join the same shutdown. Non-cooperative tasks can stall it.
    public func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        isClosed = true
        let ownedCleanups = cleanups
        cleanups.removeAll()
        let ownedTasks = tasks
        let task = Task { @MainActor in
            await ownedTasks.cancelAllAndWait()
            for cleanup in ownedCleanups.reversed() { cleanup() }
        }
        shutdownTask = task
        await task.value
    }

    deinit {
        // Best-effort lifetime fallback; explicit shutdown supplies an awaitable boundary.
        let ownedTasks = tasks
        let ownedCleanups = cleanups
        Task { @MainActor in
            await ownedTasks.cancelAllAndWait()
            for cleanup in ownedCleanups.reversed() { cleanup() }
        }
    }
}
