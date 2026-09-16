#if os(iOS)
import AVFoundation
import MediaPlayer

public enum MiniAppRemoteCommandValue: Sendable, Equatable {
    case play
    case pause
    case changePlaybackPosition(seconds: Double)
}

@MainActor
public final class MiniAppNowPlayingOwner {
    public enum Failure: Error, Sendable, Equatable { case recursiveInvalidation }
    private enum DeliveryContext { @TaskLocal static var id: UUID? }
    public typealias Handler = @MainActor @Sendable (MiniAppRemoteCommandValue) async -> Bool

    public nonisolated let id: MiniAppID
    public let session: MPNowPlayingSession
    private var generation: UInt64 = 1
    private var targets: [(MPRemoteCommand, Any)] = []
    private var activeDeliveries: Set<UUID> = []
    private var deliveryWaiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsCommands = true

    public init(id: MiniAppID, players: [AVPlayer], automaticallyPublishesNowPlayingInfo: Bool = false) {
        precondition(id.isValid && !players.isEmpty)
        self.id = id
        session = MPNowPlayingSession(players: players)
        session.automaticallyPublishesNowPlayingInfo = automaticallyPublishesNowPlayingInfo
    }

    /// `.success` means the operation was accepted for MainActor delivery, not that it completed.
    public func installStandardHandlers(
        _ handler: @escaping Handler,
        onCompletion: (@MainActor @Sendable (MiniAppRemoteCommandValue, Bool) -> Void)? = nil
    ) {
        precondition(targets.isEmpty, "Install remote targets once per owner generation.")
        add(session.remoteCommandCenter.playCommand, value: { _ in .play }, handler: handler, onCompletion: onCompletion)
        add(session.remoteCommandCenter.pauseCommand, value: { _ in .pause }, handler: handler, onCompletion: onCompletion)
        add(session.remoteCommandCenter.changePlaybackPositionCommand, value: { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return .changePlaybackPosition(seconds: event.positionTime)
        }, handler: handler, onCompletion: onCompletion)
    }

    public func requestActivation() async -> Bool { await session.becomeActiveIfPossible() }

    public func invalidate() async throws {
        if let id = DeliveryContext.id, activeDeliveries.contains(id) { throw Failure.recursiveInvalidation }
        acceptsCommands = false
        generation &+= 1
        for (command, token) in targets { command.removeTarget(token) }
        targets.removeAll()
        if !activeDeliveries.isEmpty {
            await withCheckedContinuation { deliveryWaiters.append($0) }
        }
        session.nowPlayingInfoCenter.nowPlayingInfo = nil
    }

    private func add(_ command: MPRemoteCommand,
                     value: @escaping @Sendable (MPRemoteCommandEvent) -> MiniAppRemoteCommandValue?,
                     handler: @escaping Handler,
                     onCompletion: (@MainActor @Sendable (MiniAppRemoteCommandValue, Bool) -> Void)?) {
        let installedGeneration = generation
        let target = command.addTarget { [weak self] event in
            guard let commandValue = value(event) else { return .commandFailed }
            let id = UUID()
            Task { @MainActor [weak self] in
                guard let self, self.acceptsCommands, self.generation == installedGeneration else { return }
                let completed = await self.performDelivery(id: id, value: commandValue, handler: handler)
                onCompletion?(commandValue, completed)
            }
            return .success
        }
        targets.append((command, target))
    }

    @_spi(Testing)
    public func deliverForTesting(_ value: MiniAppRemoteCommandValue, handler: @escaping Handler) async -> Bool {
        await performDelivery(id: UUID(), value: value, handler: handler)
    }

    private func performDelivery(id: UUID, value: MiniAppRemoteCommandValue,
                                 handler: @escaping Handler) async -> Bool {
        activeDeliveries.insert(id)
        let completed = await DeliveryContext.$id.withValue(id) { await handler(value) }
        activeDeliveries.remove(id)
        if activeDeliveries.isEmpty {
            let waiters = deliveryWaiters; deliveryWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        return completed
    }
}
#endif
