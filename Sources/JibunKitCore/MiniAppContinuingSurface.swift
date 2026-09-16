import Foundation

/// Native continuing work belongs to the Feature, not its current screen.
/// Closures operate on one owner's service and must be idempotent for retries.
public struct MiniAppContinuingSurface: Sendable {
    public let owner: MiniAppID
    public let id: String
    public let close: @Sendable () async throws -> Void
    public let reconcile: @Sendable () async throws -> Void
    public let endOwned: @Sendable () async throws -> Void
    public let open: @Sendable () async throws -> Void

    public init(owner: MiniAppID, id: String,
        close: @escaping @Sendable () async throws -> Void,
        reconcile: @escaping @Sendable () async throws -> Void,
        endOwned: @escaping @Sendable () async throws -> Void,
        open: @escaping @Sendable () async throws -> Void) {
        precondition(owner.isValid && MiniAppID(id).isValid)
        self.owner = owner
        self.id = id
        self.close = close
        self.reconcile = reconcile
        self.endOwned = endOwned
        self.open = open
    }
}
