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
    }

    public struct Handle: Hashable, Sendable {
        fileprivate let value: UUID
    }

    private struct Entry {
        let handle: Handle
        let kind: Kind
        let dismiss: @MainActor () async -> Void
    }

    public nonisolated let id: MiniAppID
    private var entries: [Entry] = []
    private var isConnected = false
    private var acceptsPresentations = false

    public init(id: MiniAppID) {
        precondition(id.isValid, "A presentation owner needs a valid Feature ID.")
        self.id = id
    }

    public var activeKinds: [Kind] { entries.map(\.kind) }
    public var activePresentationCount: Int { entries.count }

    /// Connects presentation teardown to this runtime generation. The supplied
    /// dismiss callbacks must return only after their UI has actually ended.
    public func connect(to runtime: MiniAppRuntime) throws {
        guard !isConnected else { throw Failure.alreadyConnected }
        try runtime.onShutdownAsync { [weak self] in
            await self?.dismissAll()
        }
        isConnected = true
        acceptsPresentations = true
    }

    /// Registers a presented surface. This does not choose where SwiftUI state
    /// lives and does not impose a host-wide modal router.
    public func begin(
        _ kind: Kind,
        dismiss: @escaping @MainActor () async -> Void
    ) throws -> Handle {
        guard acceptsPresentations else { throw Failure.notConnected }
        let handle = Handle(value: UUID())
        entries.append(Entry(handle: handle, kind: kind, dismiss: dismiss))
        return handle
    }

    /// Records user/system cancellation after the surface has already ended.
    public func didEnd(_ handle: Handle) {
        entries.removeAll { $0.handle == handle }
    }

    /// Ends one active presentation and waits for its completion callback.
    public func end(_ handle: Handle) async {
        guard let entry = entries.first(where: { $0.handle == handle }) else { return }
        await entry.dismiss()
        entries.removeAll { $0.handle == handle }
    }

    /// Closes admission first, then ends this Feature's surfaces in reverse
    /// presentation order. Another Feature's owner is never consulted.
    public func dismissAll() async {
        acceptsPresentations = false
        let owned = Array(entries.reversed())
        for entry in owned {
            await entry.dismiss()
            entries.removeAll { $0.handle == entry.handle }
        }
        isConnected = false
    }
}
