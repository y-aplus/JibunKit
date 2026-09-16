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
    private var acceptsCommands = true

    public init(id: MiniAppID, players: [AVPlayer], automaticallyPublishesNowPlayingInfo: Bool = false) {
        precondition(id.isValid && !players.isEmpty)
        self.id = id
        session = MPNowPlayingSession(players: players)
        session.automaticallyPublishesNowPlayingInfo = automaticallyPublishesNowPlayingInfo
    }

    /// `.success` means the operation was accepted for MainActor delivery, not that it completed.
    public func installStandardHandlers(_ handler: @escaping Handler) {
        precondition(targets.isEmpty, "Install remote targets once per owner generation.")
        add(session.remoteCommandCenter.playCommand, value: { _ in .play }, handler: handler)
        add(session.remoteCommandCenter.pauseCommand, value: { _ in .pause }, handler: handler)
        add(session.remoteCommandCenter.changePlaybackPositionCommand, value: { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return .changePlaybackPosition(seconds: event.positionTime)
        }, handler: handler)
    }

    public func requestActivation() async -> Bool { await session.becomeActiveIfPossible() }

    public func invalidate() {
        acceptsCommands = false
        generation &+= 1
        for (command, token) in targets { command.removeTarget(token) }
        targets.removeAll()
        session.nowPlayingInfoCenter.nowPlayingInfo = nil
    }

    private func add(_ command: MPRemoteCommand,
                     value: @escaping @Sendable (MPRemoteCommandEvent) -> MiniAppRemoteCommandValue?,
                     handler: @escaping Handler) {
        let installedGeneration = generation
        let target = command.addTarget { [weak self] event in
            guard let commandValue = value(event) else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsCommands, self.generation == installedGeneration else { return }
                _ = await handler(commandValue)
            }
            return .success
        }
        targets.append((command, target))
    }
}
#endif
