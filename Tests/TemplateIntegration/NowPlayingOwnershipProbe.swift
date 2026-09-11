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
    var aPlayCount = 0
    var aPauseCount = 0
    var bPlayCount = 0
    var bPauseCount = 0

    private var playerA: AVPlayer?
    private var playerB: AVPlayer?
    private var sessionA: MPNowPlayingSession?
    private var sessionB: MPNowPlayingSession?
    private var playTargetA: Any?
    private var pauseTargetA: Any?
    private var playTargetB: Any?
    private var pauseTargetB: Any?

    func prepareSingle() async {
        reset()
        do {
            try configureAudioSession()
            let player = AVPlayer(url: try makeToneFile(name: "feature-a", frequency: 440))
            let session = MPNowPlayingSession(players: [player])
            session.automaticallyPublishesNowPlayingInfo = false
            session.nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo(title: "Feature A")
            playerA = player
            sessionA = session
            (playTargetA, pauseTargetA) = installTargets(on: session.remoteCommandCenter, player: player, owner: "A")
            player.play()
            let requested = await session.becomeActiveIfPossible()
            result = "single-ready requested=\(requested) active=\(session.isActive)"
            print("NOW_PLAYING_CONTROL_CENTER \(result)")
        } catch {
            result = "failed: single-setup \(error)"
        }
    }

    func prepareDual() async {
        guard sessionA != nil else {
            result = "failed: prepare-single-first"
            return
        }
        do {
            let player = AVPlayer(url: try makeToneFile(name: "feature-b", frequency: 660))
            let session = MPNowPlayingSession(players: [player])
            session.automaticallyPublishesNowPlayingInfo = false
            session.nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo(title: "Feature B")
            playerB = player
            sessionB = session
            (playTargetB, pauseTargetB) = installTargets(on: session.remoteCommandCenter, player: player, owner: "B")
            player.play()
            let requested = await session.becomeActiveIfPossible()
            result = "dual-ready requested=\(requested) a-active=\(sessionA?.isActive == true) b-active=\(session.isActive)"
            print("NOW_PLAYING_CONTROL_CENTER \(result)")
        } catch {
            result = "failed: dual-setup \(error)"
        }
    }

    func removeATargets() {
        if let target = playTargetA { sessionA?.remoteCommandCenter.playCommand.removeTarget(target) }
        if let target = pauseTargetA { sessionA?.remoteCommandCenter.pauseCommand.removeTarget(target) }
        playTargetA = nil
        pauseTargetA = nil
        playerB?.play()
        result = "a-targets-removed"
        print("NOW_PLAYING_CONTROL_CENTER \(result)")
    }

    private func installTargets(on center: MPRemoteCommandCenter, player: AVPlayer, owner: String) -> (Any, Any) {
        let play = center.playCommand.addTarget { [weak self, weak player] _ in
            Task { @MainActor in
                if owner == "A" { self?.aPlayCount += 1 } else { self?.bPlayCount += 1 }
                player?.play()
                self?.logCounts(owner: owner, command: "play")
            }
            return .success
        }
        let pause = center.pauseCommand.addTarget { [weak self, weak player] _ in
            Task { @MainActor in
                if owner == "A" { self?.aPauseCount += 1 } else { self?.bPauseCount += 1 }
                player?.pause()
                self?.logCounts(owner: owner, command: "pause")
            }
            return .success
        }
        return (play, pause)
    }

    private func logCounts(owner: String, command: String) {
        print("NOW_PLAYING_CONTROL_CENTER delivered owner=\(owner) command=\(command) \(counts)")
    }

    private var counts: String {
        "a-play=\(aPlayCount) a-pause=\(aPauseCount) b-play=\(bPlayCount) b-pause=\(bPauseCount)"
    }

    private func configureAudioSession() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default)
        try audio.setActive(true)
    }

    private func nowPlayingInfo(title: String) -> [String: Any] {
        [MPMediaItemPropertyTitle: title,
         MPMediaItemPropertyArtist: "JibunKit native probe",
         MPNowPlayingInfoPropertyPlaybackRate: 1.0,
         MPMediaItemPropertyPlaybackDuration: 60.0,
         MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0]
    }

    private func makeToneFile(name: String, frequency: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8_000
        let sampleCount = sampleRate * 60
        let dataBytes = sampleCount * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(dataBytes))
        for index in 0..<sampleCount {
            let phase = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
            append(Int16(sin(phase) * 2_000))
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func reset() {
        playerA?.pause(); playerB?.pause()
        playerA = nil; playerB = nil; sessionA = nil; sessionB = nil
        playTargetA = nil; pauseTargetA = nil; playTargetB = nil; pauseTargetB = nil
        aPlayCount = 0; aPauseCount = 0; bPlayCount = 0; bPauseCount = 0
    }
}

@MainActor
enum NowPlayingOwnershipProbe {
    private static let state = NowPlayingOwnershipProbeState()
    static let definition = MiniAppDefinition(id: MiniAppID("now-playing-probe"), title: "Now Playing probe", systemImage: "play.circle") { _ in
        VStack {
            Text(state.result).accessibilityIdentifier("now-playing.result")
            Text("a-play=\(state.aPlayCount) a-pause=\(state.aPauseCount) b-play=\(state.bPlayCount) b-pause=\(state.bPauseCount)")
                .accessibilityIdentifier("now-playing.counts")
            Button("Prepare single session") { Task { await state.prepareSingle() } }.accessibilityIdentifier("now-playing.prepare-single")
            Button("Prepare dual sessions") { Task { await state.prepareDual() } }.accessibilityIdentifier("now-playing.prepare-dual")
            Button("Remove Feature A targets") { state.removeATargets() }.accessibilityIdentifier("now-playing.remove-a-targets")
        }
    }
}
