import Foundation

#if os(iOS) || os(macOS)
/// An optional Integration adapter. Files remain readable for the whole awaited
/// receive operation. Commit using receipt.id for idempotence; arbitrary Feature
/// database changes cannot be atomically committed with the shared inbox ACK.
public struct MiniAppIncomingProvider: Sendable {
    public let id: MiniAppID
    public let typeIdentifiers: [String]
    public let receive: @MainActor @Sendable (MiniAppIncomingReceipt, URL) async throws -> Void

    public init(id: MiniAppID, typeIdentifiers: [String],
                receive: @escaping @MainActor @Sendable (MiniAppIncomingReceipt, URL) async throws -> Void) {
        precondition(id.isValid && !typeIdentifiers.isEmpty && typeIdentifiers.allSatisfy { !$0.isEmpty })
        self.id = id
        self.typeIdentifiers = typeIdentifiers
        self.receive = receive
    }
}

/// One process-wide instance prevents two scenes from applying the same receipt.
/// Feature storage must still implement idempotence across process restarts.
@MainActor
public final class MiniAppIncomingDelivery {
    public static let shared = MiniAppIncomingDelivery()
    public enum Failure: Error { case alreadyDelivering, ownerMismatch, noResult }
    private var active: Set<UUID> = []

    public init() {}

    /// Use the same service as deliver so another scene cannot discard a
    /// receipt while its receiver is committing Feature-owned data.
    public func discard(id: UUID, owner: MiniAppID, inbox: MiniAppIncomingStore) async throws {
        guard active.insert(id).inserted else { throw Failure.alreadyDelivering }
        defer { active.remove(id) }
        try await Task.detached { try inbox.discard(id: id, owner: owner) }.value
    }

    public func deliver(id: UUID, provider: MiniAppIncomingProvider,
                        lifetime: MiniAppFeatureLifetime?, inbox: MiniAppIncomingStore,
                        coordinator: MiniAppRestoreCoordinator = .shared) async throws {
        guard lifetime == nil || lifetime?.id == provider.id else { throw Failure.ownerMismatch }
        guard active.insert(id).inserted else { throw Failure.alreadyDelivering }
        defer { active.remove(id) }
        try Task.checkCancellation()
        if let lifetime { try await lifetime.start() }
        // A Feature with no lifetime does not need a permanent dummy runtime.
        let runtime = lifetime?.runtime ?? MiniAppRuntime()
        let outcome = Outcome()
        let task = try runtime.start { @MainActor in
            do {
                try await coordinator.withStoreAccess(for: provider.id) {
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("jibunkit-delivery-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let receipt = try inbox.withReceipt(id: id, owner: provider.id) { receipt, folder in
                        for item in receipt.items where item.kind == .file {
                            try Task.checkCancellation()
                            try FileManager.default.copyItem(at: folder.appendingPathComponent(item.value), to: temporary.appendingPathComponent(item.value))
                        }
                        return receipt
                    }
                    let accepted = MiniAppIncomingDestination(id: provider.id, title: provider.id.rawValue, typeIdentifiers: provider.typeIdentifiers)
                    guard receipt.items.allSatisfy({ accepted.accepts($0.typeIdentifier) }) else { throw MiniAppIncomingError.invalidInput }
                    try Task.checkCancellation()
                    try await provider.receive(receipt, temporary)
                    // If receive returns successfully after a late cancellation,
                    // it has committed. Acknowledge that success, rather than
                    // inventing a failure after mutating Feature-owned data.
                    try inbox.acknowledge(id: id, owner: provider.id)
                }
                outcome.result = .success(())
            } catch { outcome.result = .failure(error) }
        }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if lifetime == nil { await runtime.shutdown() }
        guard let result = outcome.result else { throw Failure.noResult }
        try result.get()
    }

    @MainActor private final class Outcome { var result: Result<Void, Error>? }
}
#endif
