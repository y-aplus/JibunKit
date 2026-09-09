import Foundation

/// Own one scope per Feature runtime. Cancellation reaches only tasks started
/// through this instance. Operations must cooperate with Swift cancellation;
/// cancelling is not proof that an operation has stopped or released a resource.
@MainActor
public final class MiniAppTaskScope {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    @discardableResult
    public func start(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }

    /// Requests cancellation; the returned task handles can be awaited when
    /// callers need to observe completion before releasing shared resources.
    public func cancelAll() {
        for task in tasks.values { task.cancel() }
    }

    /// Cancels and joins the tasks owned at entry. Work started while awaiting
    /// belongs to a later batch and is not cancelled. Call from the runtime's
    /// coordinator, never from one of this scope's operations (which would wait
    /// for itself). Non-cooperative operations can prevent completion.
    public func cancelAllAndWait() async {
        let owned = Array(tasks.values)
        for task in owned { task.cancel() }
        for task in owned { await task.value }
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }
}
