// Included only in the isolated signed CI host, never in a distributed IPA.
import AVFoundation
import JibunKitCore
import MediaPlayer
import Observation
import SwiftUI

@MainActor
@Observable
final class NowPlayingOwnershipProbeState {
    var result = "idle"

    func run() async {
        result = "running"

        let playerA = AVPlayer()
        let playerB = AVPlayer()
        let sessionA = MPNowPlayingSession(players: [playerA])
        let sessionB = MPNowPlayingSession(players: [playerB])
        sessionA.automaticallyPublishesNowPlayingInfo = false
        sessionB.automaticallyPublishesNowPlayingInfo = false

        guard sessionA.players.count == 1, sessionA.players[0] === playerA,
              sessionB.players.count == 1, sessionB.players[0] === playerB,
              sessionA.nowPlayingInfoCenter !== sessionB.nowPlayingInfoCenter,
              sessionA.remoteCommandCenter !== sessionB.remoteCommandCenter else {
            result = "failed: session-boundaries"
            return
        }

        sessionA.nowPlayingInfoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "Feature A"]
        sessionB.nowPlayingInfoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "Feature B"]
        guard sessionA.nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Feature A",
              sessionB.nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Feature B" else {
            result = "failed: now-playing-info"
            return
        }

        let targetA = sessionA.remoteCommandCenter.playCommand.addTarget { _ in .success }
        let targetB = sessionB.remoteCommandCenter.playCommand.addTarget { _ in .success }
        guard (targetA as AnyObject) !== (targetB as AnyObject) else {
            result = "failed: command-targets"
            return
        }
        sessionA.remoteCommandCenter.playCommand.removeTarget(targetA)

        let activatedA = await sessionA.becomeActiveIfPossible()
        let aActivationWasConsistent = !activatedA || sessionA.isActive
        let activatedB = await sessionB.becomeActiveIfPossible()
        let bActivationWasConsistent = !activatedB || sessionB.isActive
        let activeSelectionWasExclusive = !(sessionA.isActive && sessionB.isActive)

        // Removing A's player and command target must not mutate B's session.
        sessionA.removePlayer(playerA)
        guard sessionA.players.isEmpty,
              sessionB.players.count == 1, sessionB.players[0] === playerB,
              sessionB.nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Feature B" else {
            sessionB.remoteCommandCenter.playCommand.removeTarget(targetB)
            result = "failed: cross-owner-removal"
            return
        }
        sessionB.remoteCommandCenter.playCommand.removeTarget(targetB)

        guard aActivationWasConsistent,
              bActivationWasConsistent,
              activeSelectionWasExclusive else {
            result = "failed: active-selection"
            return
        }

        print("NOW_PLAYING_NATIVE centers=independent players=independent targets=scoped " +
              "a-active=\(activatedA) b-active=\(activatedB)")
        result = "passed: centers=independent a-active=\(activatedA) b-active=\(activatedB)"
    }
}

@MainActor
enum NowPlayingOwnershipProbe {
    private static let state = NowPlayingOwnershipProbeState()

    static let definition = MiniAppDefinition(
        id: MiniAppID("now-playing-probe"),
        title: "Now Playing probe",
        systemImage: "play.circle"
    ) { _ in
        VStack {
            Text(state.result).accessibilityIdentifier("now-playing.result")
            Button("Run native Now Playing comparison") {
                Task { await state.run() }
            }.accessibilityIdentifier("now-playing.run")
        }
    }
}
