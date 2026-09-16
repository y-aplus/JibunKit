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

    public func invalidate() async {
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
                self.activeDeliveries.insert(id)
                let completed = await handler(commandValue)
                onCompletion?(commandValue, completed)
                self.activeDeliveries.remove(id)
                if self.activeDeliveries.isEmpty {
                    let waiters = self.deliveryWaiters; self.deliveryWaiters.removeAll()
                    waiters.forEach { $0.resume() }
                }
            }
            return .success
        }
        targets.append((command, target))
    }
}
#endif
