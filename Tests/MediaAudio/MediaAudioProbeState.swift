#if os(iOS)
import AVFoundation
import JibunKitCore
import MediaPlayer
import Observation

@MainActor @Observable
final class MediaAudioProbeState {
    let driver = MiniAppNativeAudioSessionDriver()
    let coordinator: MiniAppAudioSessionCoordinator
    var status = "待機中"
    var detail = "owners=0"
    var microphoneConsent = UserDefaults.standard.bool(forKey: "media-audio.microphone-consent")
    var playerGeneration: UInt64 = 0
    var recorderGeneration: UInt64 = 0
    var playerCommandCount = 0
    var recorderSampleCount: AVAudioFramePosition = 0
    var errorText = "なし"
    var sceneSummary = "scene未接続"

    private(set) var playerLease: MiniAppAudioSessionCoordinator.Lease?
    private(set) var recorderLease: MiniAppAudioSessionCoordinator.Lease?
    private var player: AVPlayer?
    private var nowPlaying: MiniAppNowPlayingOwner?
    private var recorder: AVAudioRecorder?
    private var recordedPlayer: AVAudioPlayer?
    @ObservationIgnored private var pendingRecorderConflict: MiniAppAudioSessionCoordinator.Conflict?

    var playerTime: Double { player?.currentTime().seconds ?? 0 }
    var nowPlayingTitle: String? { nowPlaying?.session.nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String }

    init() {
        coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        try! driver.connect(to: coordinator)
    }

    func setMicrophoneConsent(_ allowed: Bool) {
        microphoneConsent = allowed
        UserDefaults.standard.set(allowed, forKey: "media-audio.microphone-consent")
        status = allowed ? "Feature microphone同意済み" : "Feature microphone未同意"
    }

    func receiveSceneActivity(_ activity: MiniAppSceneActivity) {
        sceneSummary = "\(activity.featureID.rawValue):\(String(describing: activity.phase)) selected=\(activity.isSelected)"
    }

    func startPlayer() async {
        guard playerLease == nil else { return }
        do {
            let playback = MiniAppAudioProfile(category: .playback, mode: .spokenAudio)
            let duplex = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
            let admission = try await coordinator.acquire(owner: MiniAppID("media-audio-player"),
                request: .init(acceptableProfiles: [playback, duplex], purpose: "ローカル音声の再生"),
                stop: { [weak self] in self?.stopPlayerProducer() },
                receive: { [weak self] in self?.handlePlayer($0) })
            guard case .acquired(let lease) = admission else { status = "再生競合: 明示切替が必要"; return }
            let localPlayer = AVPlayer(url: try Self.makeToneFile())
            let owner = MiniAppNowPlayingOwner(id: lease.owner, players: [localPlayer])
            owner.session.nowPlayingInfoCenter.nowPlayingInfo = [
                MPMediaItemPropertyTitle: "JibunKit Local Tone", MPMediaItemPropertyArtist: "MediaAudioProbe",
                MPNowPlayingInfoPropertyPlaybackRate: 1.0, MPNowPlayingInfoPropertyPlaybackDuration: 8.0]
            owner.installStandardHandlers { [weak self, weak localPlayer] command in
                guard let self else { return false }
                switch command {
                case .play: localPlayer?.play(); try? self.coordinator.updateIntent(.active, for: lease)
                case .pause: localPlayer?.pause(); try? self.coordinator.updateIntent(.stoppedByUser, for: lease)
                case .changePlaybackPosition(let seconds):
                    localPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                }
                self.playerCommandCount += 1
                return true
            }
            player = localPlayer; nowPlaying = owner; playerLease = lease; playerGeneration = lease.generation
            try coordinator.updateIntent(.active, for: lease)
            localPlayer.play(); _ = await owner.requestActivation()
            status = "再生中"; refreshDetail()
        } catch { fail("再生開始", error) }
    }

    func stopPlayer() async {
        guard let lease = playerLease else { return }
        do { try coordinator.updateIntent(.stoppedByUser, for: lease); try await coordinator.release(lease) }
        catch { fail("再生停止", error) }
        playerLease = nil; refreshDetail()
    }

    func reserveRecorderAudio() async throws {
        guard recorderLease == nil else { return }
        let duplex = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
        let admission = try await coordinator.acquire(owner: MiniAppID("media-audio-recorder"),
            request: .init(acceptableProfiles: [duplex], purpose: "microphone録音", allowsInterruptionResume: false),
            stop: { [weak self] in self?.stopRecorderProducer() },
            receive: { [weak self] in self?.handleRecorder($0) })
        switch admission {
        case .acquired(let lease): recorderLease = lease; recorderGeneration = lease.generation
        case .conflict(let conflict):
            pendingRecorderConflict = conflict
            status = "AudioSession競合: 明示切替が必要"
            errorText = "停止対象: \(conflict.incumbentOwners.map(\.rawValue).sorted().joined(separator: ", ")) / \(conflict.reason)"
            throw ProbeError.explicitSwitchRequired
        }
        refreshDetail()
    }

    func confirmRecorderReplacement() async {
        guard let conflict = pendingRecorderConflict else { return }
        do {
            let lease = try await coordinator.resolve(conflict, as: .replaceOwners(conflict.incumbentOwners))
            pendingRecorderConflict = nil; recorderLease = lease; recorderGeneration = lease.generation
            await startRecording()
        } catch { pendingRecorderConflict = nil; fail("明示切替", error) }
    }

    func startRecording() async {
        guard microphoneConsent else { errorText = "Feature microphone同意が必要"; status = "録音拒否"; return }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorText = "OS microphone許可なし（設定で変更可能）"; status = "録音拒否"; return
        }
        do {
            try await reserveRecorderAudio()
            try? FileManager.default.removeItem(at: Self.recordingURL)
            let value = try AVAudioRecorder(url: Self.recordingURL, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            guard value.prepareToRecord(), value.record() else { throw ProbeError.recordingDidNotStart }
            recorder = value
            if let lease = recorderLease { try coordinator.updateIntent(.active, for: lease) }
            status = "録音中"; errorText = "なし"; refreshDetail()
        } catch ProbeError.explicitSwitchRequired {
            // The reason and selected incumbents remain visible until explicit confirmation.
        } catch { fail("録音開始", error) }
    }

    func stopRecordingAndPlay() async {
        recorderSampleCount = AVAudioFramePosition((recorder?.currentTime ?? 0) * 16_000)
        recorder?.stop(); recorder = nil
        do {
            let value = try AVAudioPlayer(contentsOf: Self.recordingURL)
            guard value.prepareToPlay(), value.play() else { throw ProbeError.playbackDidNotStart }
            recordedPlayer = value; status = "録音再生中 samples=\(recorderSampleCount)"
        } catch { fail("録音再生", error) }
    }

    func releaseRecorder() async {
        guard let lease = recorderLease else { return }
        do { try coordinator.updateIntent(.stoppedByUser, for: lease); try await coordinator.release(lease) }
        catch { fail("録音解放", error) }
        recorderLease = nil; refreshDetail()
    }

    func reset() async {
        await stopPlayer()
        await releaseRecorder()
        pendingRecorderConflict = nil
        status = "待機中"; errorText = "なし"; refreshDetail()
    }

    private func stopPlayerProducer() {
        player?.pause(); nowPlaying?.invalidate(); nowPlaying = nil; player = nil; playerLease = nil
        refreshDetail()
    }
    private func stopRecorderProducer() {
        recorder?.stop(); recorder = nil; recordedPlayer?.stop(); recordedPlayer = nil; recorderLease = nil
        refreshDetail()
    }
    private func handlePlayer(_ event: MiniAppAudioEvent) {
        switch event {
        case .interruptionBegan: player?.pause(); status = "再生中断"
        case .interruptionEnded(let candidate): status = candidate ? "再開候補（自動再生なし）" : "再開不可"
        case .routeChanged(let reason):
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                player?.pause(); if let playerLease { try? coordinator.updateIntent(.stoppedForRouteChange, for: playerLease) }
            }
            status = "経路変更 reason=\(reason)"
        case .mediaServicesReset: status = "media services reset（再構築必要）"
        }
    }
    private func handleRecorder(_ event: MiniAppAudioEvent) {
        if case .interruptionBegan = event { recorder?.stop(); status = "録音中断" }
    }
    private func refreshDetail() {
        detail = "owners=\(coordinator.activeOwners.count) playerGen=\(playerGeneration) recorderGen=\(recorderGeneration) commands=\(playerCommandCount)"
    }
    private func fail(_ operation: String, _ error: Error) { errorText = "\(operation): \(error)"; status = "失敗"; refreshDetail() }

    private static let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("media-audio-recording.caf")
    private static func makeToneFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("media-audio-tone.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 8_000, count = rate * 8
        var data = Data()
        func append<T: FixedWidthInteger>(_ input: T) { var value = input.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + count * 2)); data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(count * 2))
        for index in 0..<count { append(Int16(sin(2 * .pi * 440 * Double(index) / Double(rate)) * 2_000)) }
        try data.write(to: url, options: .atomic); return url
    }
    private enum ProbeError: Error { case recordingDidNotStart, playbackDidNotStart, explicitSwitchRequired }
}
#endif
