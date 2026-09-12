import Foundation
#if os(iOS)
import Observation
#endif

/// One explicit lifetime per Feature owner, independent of which scene/view is
/// currently selected. Configuration registers resources with each new runtime.
/// Do not call start/stop from work owned by that runtime: stop joins owned work.
#if os(iOS)
@Observable
#endif
@MainActor
public final class MiniAppFeatureLifetime {
    public enum State: Equatable, Sendable {
        case stopped, starting, running, stopping
        case failed(String)
    }
    public enum Failure: Error { case suspendedForRestore }

    public nonisolated let id: MiniAppID
    public private(set) var state: State = .stopped
    /// May be starting or closing; use start() before admitting work and use
    /// this lifetime's stop(), rather than directly shutting down its runtime.
    public private(set) var runtime: MiniAppRuntime?
    private let configure: @MainActor @Sendable (MiniAppRuntime) async throws -> Void
    private var starting: Task<Void, Error>?
    private var stopping: Task<Void, Never>?
    private var suspendedForRestore = false
    private var resumeAfterRestore = false

    public init(id: MiniAppID,
                configure: @escaping @MainActor @Sendable (MiniAppRuntime) async throws -> Void = { _ in }) {
        precondition(id.isValid, "A Feature lifetime needs a valid owner ID.")
        self.id = id
        self.configure = configure
    }

    /// Concurrent callers join one configuration. Cancelling a view's waiting
    /// task does not cancel Feature-owned startup/work; explicit stop does.
    public func start() async throws {
        try Task.checkCancellation()
        while let stopping { await stopping.value }
        try Task.checkCancellation()
        guard !suspendedForRestore else { throw Failure.suspendedForRestore }
        if let starting {
            try await starting.value
            try Task.checkCancellation()
            return
        }
        if let runtime {
            if !runtime.isClosed { return }
            // If a client directly closed the runtime, join resource release
            // before replacing it, rather than overlapping two generations.
            await stopRuntime()
            try Task.checkCancellation()
            return try await start()
        }
        let created = MiniAppRuntime()
        runtime = created
        state = .starting
        let task = Task { @MainActor in
            defer { self.starting = nil }
            do {
                try Task.checkCancellation()
                try await self.configure(created)
                try Task.checkCancellation()
                self.state = .running
            } catch {
                // A failed configuration may already own tasks/connections.
                // It remains unavailable until all registered cleanup finishes.
                await created.shutdown()
                self.runtime = nil
                if self.stopping == nil { self.state = .failed(error.localizedDescription) }
                throw error
            }
        }
        starting = task
        try await task.value
        try Task.checkCancellation()
    }

    /// Closes this owner only. No view disappearance automatically calls this.
    /// An explicit stop during restore also cancels automatic resumption.
    public func stop() async {
        resumeAfterRestore = false
        await stopRuntime()
    }

    private func stopRuntime() async {
        if let stopping { await stopping.value; return }
        guard runtime != nil || starting != nil else { state = .stopped; return }
        state = .stopping
        let startup = starting
        startup?.cancel()
        let task = Task { @MainActor in
            // Configuration must relinquish resources before a new generation.
            // Non-cooperative configuration can stall this boundary, just as
            // non-cooperative work can stall MiniAppRuntime.shutdown().
            _ = await startup?.result
            await self.runtime?.shutdown()
            self.runtime = nil
            self.state = .stopped
            self.stopping = nil
        }
        stopping = task
        await task.value
    }

    /// Use the same coordinator for all restore/maintenance entrances. Restore
    /// of an unopened Feature must not launch its work as a side effect.
    public var restoreLifecycle: MiniAppRestoreLifecycle {
        MiniAppRestoreLifecycle(stop: { try await self.suspend() }, resume: { try await self.resume() })
    }

    private func suspend() async throws {
        guard !suspendedForRestore else { throw Failure.suspendedForRestore }
        suspendedForRestore = true
        resumeAfterRestore = state == .running || state == .starting
        await stopRuntime()
    }

    private func resume() async throws {
        let shouldResume = resumeAfterRestore
        resumeAfterRestore = false
        suspendedForRestore = false
        if shouldResume {
            // Resumption is cleanup of an admitted maintenance operation. Its
            // caller may have been cancelled during apply; still restore a
            // usable generation before returning that cancellation/failure.
            let restarting = Task { @MainActor in try await self.start() }
            try await restarting.value
        }
    }
}
