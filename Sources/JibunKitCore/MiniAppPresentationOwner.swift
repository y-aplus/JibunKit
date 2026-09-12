import Foundation

/// Tracks presentations owned by one Feature lifetime. Create one owner per
/// Feature and connect it to each new runtime generation before presenting UI.
@MainActor
public final class MiniAppPresentationOwner {
    public enum Kind: Sendable, Hashable {
        case sheet
        case fullScreenCover
        case uiViewController
    }

    public enum Failure: Error, Sendable, Equatable {
        case notConnected
        case alreadyConnected
        case runtimeClosed
    }

    public struct Handle: Hashable, Sendable {
        fileprivate let value: UUID
        fileprivate let generation: UUID
    }

    private struct Entry {
        let handle: Handle
        let kind: Kind
        let dismiss: @MainActor () async -> Void
    }

    public nonisolated let id: MiniAppID
    private var entries: [Entry] = []
    private weak var runtime: MiniAppRuntime?
    private var generation: UUID?
    private var acceptsPresentations = false
    private var dismissalTasks: [Handle: Task<Void, Never>] = [:]
    private var isDismissingAll = false
    private var dismissalWaiters: [CheckedContinuation<Void, Never>] = []

    public init(id: MiniAppID) {
        precondition(id.isValid, "A presentation owner needs a valid Feature ID.")
        self.id = id
    }

    public var activeKinds: [Kind] { entries.map(\.kind) }
    public var activePresentationCount: Int { entries.count }

    /// Connects presentation teardown to this runtime generation. The supplied
    /// dismiss callbacks must return only after their UI has actually ended.
    public func connect(to runtime: MiniAppRuntime) throws {
        guard generation == nil else { throw Failure.alreadyConnected }
        guard !runtime.isClosed else { throw Failure.runtimeClosed }
        let generation = UUID()
        try runtime.onShutdownAsync { [weak self] in
            await self?.dismissAll(generation: generation)
        }
        self.runtime = runtime
        self.generation = generation
        acceptsPresentations = true
    }

    /// Registers a presented surface. This does not choose where SwiftUI state
    /// lives and does not impose a host-wide modal router.
    public func begin(
        _ kind: Kind,
        dismiss: @escaping @MainActor () async -> Void
    ) throws -> Handle {
        guard acceptsPresentations, let generation, runtime?.isClosed == false
        else { throw Failure.notConnected }
        let handle = Handle(value: UUID(), generation: generation)
        entries.append(Entry(handle: handle, kind: kind, dismiss: dismiss))
        return handle
    }

    /// Records user/system cancellation after the surface has already ended.
    public func didEnd(_ handle: Handle) {
        guard handle.generation == generation else { return }
        entries.removeAll { $0.handle == handle }
    }

    /// Ends one active presentation and waits for its completion callback.
    public func end(_ handle: Handle) async {
        if let task = dismissalTasks[handle] {
            await task.value
            return
        }
        guard let entry = entries.first(where: { $0.handle == handle }) else { return }
        let task = Task { @MainActor in await entry.dismiss() }
        dismissalTasks[handle] = task
        await task.value
        entries.removeAll { $0.handle == handle }
        dismissalTasks[handle] = nil
    }

    /// Closes admission first, then ends this Feature's surfaces in reverse
    /// presentation order. Another Feature's owner is never consulted.
    public func dismissAll() async {
        guard let generation else { return }
        await dismissAll(generation: generation)
    }

    private func dismissAll(generation requestedGeneration: UUID) async {
        guard generation == requestedGeneration else { return }
        if isDismissingAll {
            await withCheckedContinuation { dismissalWaiters.append($0) }
            return
        }
        isDismissingAll = true
        acceptsPresentations = false
        var owned = entries.reversed().map(\.handle)
        // Native UI can acknowledge didEnd before its registered callback has
        // finished additional teardown. Join those in-flight callbacks too.
        owned += dismissalTasks.keys.filter { !owned.contains($0) }
        for handle in owned {
            await end(handle)
        }
        runtime = nil
        generation = nil
        isDismissingAll = false
        let waiters = dismissalWaiters
        dismissalWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
