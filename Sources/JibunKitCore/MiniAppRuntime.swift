import Foundation

/// A cooperative lifetime for Feature work and its resources. Construct a new
/// runtime when restarting; a shut-down runtime never accepts new work.
@MainActor
public final class MiniAppRuntime {
    public enum Failure: Error { case closed }

    public struct ShutdownProgress: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            case active
            case waitingForTasks
            case runningCleanups
            case completed
        }

        public let phase: Phase
        public let pendingTaskCount: Int
        public let remainingCleanupCount: Int
        public let startedAt: Date?
    }

    public private(set) var isClosed = false
    private let tasks = MiniAppTaskScope()
    private var cleanups: [@MainActor @Sendable () async -> Void] = []
    private var shutdownTask: Task<Void, Never>?
    private var shutdownPhase: ShutdownProgress.Phase = .active
    private var shutdownPendingTaskCount = 0
    private var shutdownRemainingCleanupCount = 0
    private var shutdownStartedAt: Date?

    public init() {}

    /// A point-in-time view of shutdown. Cancellation alone never advances the
    /// task count; a task stops being pending only after its operation returns.
    public var shutdownProgress: ShutdownProgress {
        if shutdownPhase == .active {
            return ShutdownProgress(
                phase: .active,
                pendingTaskCount: tasks.activeTaskCount,
                remainingCleanupCount: cleanups.count,
                startedAt: nil
            )
        }
        return ShutdownProgress(
            phase: shutdownPhase,
            pendingTaskCount: shutdownPendingTaskCount,
            remainingCleanupCount: shutdownRemainingCleanupCount,
            startedAt: shutdownStartedAt
        )
    }

    @discardableResult
    public func start(_ operation: @escaping @Sendable () async -> Void) throws -> Task<Void, Never> {
        guard !isClosed else { throw Failure.closed }
        return tasks.start(operation)
    }

    /// Register resource cleanup before starting work which uses that resource.
    /// Runs in reverse registration order, after owned tasks finish.
    public func onShutdown(_ cleanup: @escaping @MainActor @Sendable () -> Void) throws {
        guard !isClosed else { throw Failure.closed }
        cleanups.append { cleanup() }
    }

    /// Await asynchronous resource release after owned tasks finish. Registered
    /// synchronous and asynchronous cleanups share one reverse-order sequence.
    /// Cleanup must finish; unbounded waits also prevent shutdown from finishing.
    public func onShutdownAsync(_ cleanup: @escaping @MainActor @Sendable () async -> Void) throws {
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
        shutdownPhase = .waitingForTasks
        shutdownPendingTaskCount = ownedTasks.activeTaskCount
        shutdownRemainingCleanupCount = ownedCleanups.count
        shutdownStartedAt = Date()
        let task = Task { @MainActor [weak self] in
            await ownedTasks.cancelAllAndWait { [weak self] remaining in
                self?.shutdownPendingTaskCount = remaining
            }
            self?.shutdownPhase = .runningCleanups
            for cleanup in ownedCleanups.reversed() {
                await cleanup()
                if let self { self.shutdownRemainingCleanupCount -= 1 }
            }
            self?.shutdownPhase = .completed
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
            for cleanup in ownedCleanups.reversed() { await cleanup() }
        }
    }
}
