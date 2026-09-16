#if os(iOS)
import AVFoundation
import JibunKitCore
import MediaPlayer
import Observation

@MainActor protocol MediaAudioRecordingBackend: AnyObject {
    func start(at url: URL) throws
    func stopAndPlay(at url: URL) throws -> AVAudioFramePosition
    func stop()
}

@MainActor final class MediaAudioNativeRecordingBackend: MediaAudioRecordingBackend {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    func start(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let value = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        guard value.prepareToRecord(), value.record() else { throw MediaAudioProbeError.recordingDidNotStart }
        recorder = value
    }
    func stopAndPlay(at url: URL) throws -> AVAudioFramePosition {
        let frames = AVAudioFramePosition((recorder?.currentTime ?? 0) * 16_000)
        recorder?.stop(); recorder = nil
        let value = try AVAudioPlayer(contentsOf: url)
        guard value.prepareToPlay(), value.play() else { throw MediaAudioProbeError.playbackDidNotStart }
        player = value; return frames
    }
    func stop() { recorder?.stop(); recorder = nil; player?.stop(); player = nil }
}

enum MediaAudioProbeError: Error { case recordingDidNotStart, playbackDidNotStart, explicitSwitchRequired }

@MainActor @Observable
final class MediaAudioProbeState {
    let coordinator: MiniAppAudioSessionCoordinator
    var playerStatus = "待機中"
    var recorderStatus = "待機中"
    var detail = "owners=0"
    var playerGeneration: UInt64 = 0
    var recorderGeneration: UInt64 = 0
    var playerCommandCount = 0
    var recorderSampleCount: AVAudioFramePosition = 0
    var playerError = "なし"
    var recorderError = "なし"
    var sceneSummary = "scene未接続"

    private(set) var playerLease: MiniAppAudioSessionCoordinator.Lease?
    private(set) var recorderLease: MiniAppAudioSessionCoordinator.Lease?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var nowPlaying: MiniAppNowPlayingOwner?
    private let permission: @MainActor @Sendable () async -> Bool
    private let recording: any MediaAudioRecordingBackend
    private let beforePlayerStop: @MainActor @Sendable () async throws -> Void
    private var playerOperation: UInt64 = 0
    private var recorderOperation: UInt64 = 0
    private var consentGeneration: UInt64 = 0
    private var featureConsentAllowed = false
    @ObservationIgnored private var pendingRecorderConflict: MiniAppAudioSessionCoordinator.Conflict?

    var playerTime: Double { player?.currentTime().seconds ?? 0 }
    var nowPlayingTitle: String? { nowPlaying?.session.nowPlayingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String }

    init(coordinator: MiniAppAudioSessionCoordinator = MiniAppNativeAudio.coordinator,
         permission: @escaping @MainActor @Sendable () async -> Bool = { await AVAudioApplication.requestRecordPermission() },
         recording: any MediaAudioRecordingBackend = MediaAudioNativeRecordingBackend(),
         beforePlayerStop: @escaping @MainActor @Sendable () async throws -> Void = {}) {
        self.coordinator = coordinator; self.permission = permission; self.recording = recording
        self.beforePlayerStop = beforePlayerStop
    }

    func receiveSceneActivity(_ activity: MiniAppSceneActivity) {
        sceneSummary = "\(activity.featureID.rawValue):\(String(describing: activity.phase)) selected=\(activity.isSelected)"
    }

    func updateFeatureConsent(_ allowed: Bool) {
        if featureConsentAllowed != allowed { featureConsentAllowed = allowed; consentGeneration &+= 1 }
    }

    func startPlayer() async {
        guard playerLease == nil else {
            if let lease = playerLease {
                do { try await coordinator.activateForUserAction(lease); player?.play(); playerStatus = "再生再開" }
                catch { playerError = "再開: \(error)" }
            }
            return
        }
        playerOperation &+= 1; let operation = playerOperation
        var acquiredLease: MiniAppAudioSessionCoordinator.Lease?
        do {
            let playback = MiniAppAudioProfile(category: .playback, mode: .spokenAudio)
            let duplex = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
            let admission = try await coordinator.acquire(owner: MiniAppID("media-audio-player"),
                request: .init(acceptableProfiles: [playback, duplex], purpose: "ローカル音声の再生"),
                stop: { [weak self] in try await self?.stopPlayerProducer() }, receive: { [weak self] in self?.handlePlayer($0) })
            guard operation == playerOperation else { if case .acquired(let lease) = admission { try? await coordinator.release(lease) }; return }
            guard case .acquired(let lease) = admission else { playerStatus = "再生競合"; return }
            acquiredLease = lease
            playerLease = lease; playerGeneration = lease.generation
            try coordinator.updateIntent(.active, for: lease)
            try await installPlayerNative(for: lease)
            guard playerOperation == operation, playerLease == lease else { return }
            playerStatus = "loop再生中"; playerError = "なし"; refreshDetail()
        } catch {
            if let acquiredLease { try? await coordinator.release(acquiredLease) }
            playerLease = nil; playerError = "再生開始: \(error)"; playerStatus = "失敗"
        }
    }

    func stopPlayer() async {
        playerOperation &+= 1
        guard let lease = playerLease else { return }
        do {
            try coordinator.updateIntent(.stoppedByUser, for: lease); try await coordinator.release(lease)
            playerLease = nil; playerStatus = "停止済み"
        } catch { playerError = "再生停止: \(error)"; playerStatus = "停止失敗" }
        refreshDetail()
    }

    func reserveRecorderAudio() async throws {
        guard recorderLease == nil else { return }
        let duplex = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
        let admission = try await coordinator.acquire(owner: MiniAppID("media-audio-recorder"),
            request: .init(acceptableProfiles: [duplex], purpose: "microphone録音", allowsInterruptionResume: false),
            stop: { [weak self] in self?.stopRecorderProducer() }, receive: { [weak self] in self?.handleRecorder($0) })
        switch admission {
        case .acquired(let lease): recorderLease = lease; recorderGeneration = lease.generation
        case .conflict(let conflict):
            pendingRecorderConflict = conflict; recorderStatus = "AudioSession競合: 明示切替が必要"
            recorderError = "停止対象: \(conflict.incumbentOwners.map(\.rawValue).sorted().joined(separator: ", "))"
            throw MediaAudioProbeError.explicitSwitchRequired
        }
        refreshDetail()
    }

    func confirmRecorderReplacement(featureConsent: Bool) async {
        guard let conflict = pendingRecorderConflict else { return }
        updateFeatureConsent(featureConsent)
        guard featureConsentAllowed else { recorderError = "Feature microphone同意が必要"; return }
        let consent = consentGeneration
        recorderOperation &+= 1; let operation = recorderOperation
        guard await permission(), operation == recorderOperation, consent == consentGeneration, featureConsentAllowed else {
            if operation == recorderOperation { recorderError = "OS microphone許可なし" }
            return
        }
        do {
            let lease = try await coordinator.resolve(conflict, as: .replaceOwners(conflict.incumbentOwners))
            guard operation == recorderOperation else { try? await coordinator.release(lease); return }
            pendingRecorderConflict = nil; recorderLease = lease; recorderGeneration = lease.generation
            if conflict.incumbentOwners.contains(MiniAppID("media-audio-player")) { playerLease = nil }
            try await coordinator.activateForUserAction(lease)
            guard operation == recorderOperation, consent == consentGeneration, featureConsentAllowed else {
                await releaseRecorder(); return
            }
            try recording.start(at: Self.recordingURL)
            try coordinator.updateIntent(.active, for: lease)
            recorderStatus = "録音中"; recorderError = "なし"; refreshDetail()
        } catch {
            if recorderLease != nil { await releaseRecorder() }
            pendingRecorderConflict = nil; recorderError = "明示切替: \(error)"; recorderStatus = "失敗"
        }
    }

    func startRecording(featureConsent: Bool) async {
        updateFeatureConsent(featureConsent)
        guard featureConsentAllowed else { recorderError = "Feature microphone同意が必要"; recorderStatus = "録音拒否"; return }
        let consent = consentGeneration
        recorderOperation &+= 1; let operation = recorderOperation
        let granted = await permission()
        guard operation == recorderOperation, consent == consentGeneration, featureConsentAllowed else { return }
        guard granted else {
            if recorderLease != nil { await releaseRecorder() }
            recorderError = "OS microphone許可なし"; recorderStatus = "録音拒否"
            return
        }
        var acquiredHere = false
        do {
            if recorderLease == nil { try await reserveRecorderAudio(); acquiredHere = true }
            guard operation == recorderOperation else { if acquiredHere { await releaseRecorder() }; return }
            if let lease = recorderLease { try await coordinator.activateForUserAction(lease) }
            guard operation == recorderOperation, consent == consentGeneration, featureConsentAllowed else {
                if recorderLease != nil { await releaseRecorder() }; return
            }
            try recording.start(at: Self.recordingURL)
            guard operation == recorderOperation else { recording.stop(); if acquiredHere { await releaseRecorder() }; return }
            if let lease = recorderLease { try coordinator.updateIntent(.active, for: lease) }
            recorderStatus = "録音中"; recorderError = "なし"; refreshDetail()
        } catch MediaAudioProbeError.explicitSwitchRequired {
        } catch {
            if acquiredHere { await releaseRecorder() }
            recorderError = "録音開始: \(error)"; recorderStatus = "失敗"
        }
    }

    func stopRecordingAndPlay() async {
        do { recorderSampleCount = try recording.stopAndPlay(at: Self.recordingURL); recorderStatus = "録音再生中 samples=\(recorderSampleCount)" }
        catch { recorderError = "録音再生: \(error)"; recorderStatus = "失敗" }
    }

    func releaseRecorder() async {
        recorderOperation &+= 1
        guard let lease = recorderLease else { return }
        do {
            try coordinator.updateIntent(.stoppedByUser, for: lease); try await coordinator.release(lease)
            recorderLease = nil; recorderStatus = "停止済み"
        } catch { recorderError = "録音解放: \(error)"; recorderStatus = "停止失敗" }
        refreshDetail()
    }

    func reset() async { await stopPlayer(); await releaseRecorder(); pendingRecorderConflict = nil }

    func recoverAudioSession() async {
        do { try await coordinator.recoverSession(); playerStatus = "AudioSession復旧済み"; recorderStatus = "AudioSession復旧済み" }
        catch { playerError = "AudioSession復旧: \(error)"; recorderError = playerError }
        refreshDetail()
    }

    func stopPlayerForLifetime() async {
        await stopPlayer()
        if let lease = playerLease {
            await coordinator.waitForRelease(lease)
            playerLease = nil
        }
    }
    func stopRecorderForLifetime() async {
        await releaseRecorder()
        if let lease = recorderLease {
            await coordinator.waitForRelease(lease)
            recorderLease = nil
        }
    }

    private func stopPlayerProducer() async throws {
        try await beforePlayerStop()
        player?.pause(); try await nowPlaying?.invalidate(); nowPlaying = nil; looper = nil; player = nil
    }
    private func stopRecorderProducer() { recording.stop() }
    private func handlePlayer(_ event: MiniAppAudioEvent) {
        switch event {
        case .interruptionBegan: player?.pause(); playerStatus = "再生中断"
        case .interruptionEnded(let candidate): playerStatus = candidate ? "再開可能（操作待ち）" : "再開不可"
        case .routeChanged(let reason):
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                player?.pause(); if let playerLease { try? coordinator.updateIntent(.stoppedForRouteChange, for: playerLease) }
            }
            playerStatus = "経路変更 reason=\(reason)"
        case .mediaServicesReset:
            playerStatus = "media reset: native再構築中"
            Task { @MainActor [weak self] in await self?.rebuildPlayerAfterReset() }
        case .released:
            playerLease = nil
            playerStatus = "停止済み"
        }
    }
    private func handleRecorder(_ event: MiniAppAudioEvent) {
        if case .released = event { recorderLease = nil; recorderStatus = "停止済み" }
        if case .interruptionBegan = event { recording.stop(); recorderStatus = "録音中断" }
        if case .mediaServicesReset = event { recording.stop(); recorderStatus = "media reset: 再構築待ち" }
    }
    private func refreshDetail() {
        detail = "owners=\(coordinator.activeOwners.count) playerGen=\(playerGeneration) recorderGen=\(recorderGeneration) commands=\(playerCommandCount) state=\(coordinator.sessionState)"
    }
    private func installPlayerNative(for lease: MiniAppAudioSessionCoordinator.Lease) async throws {
        let item = AVPlayerItem(url: try Self.makeToneFile())
        let localPlayer = AVQueuePlayer()
        let localLooper = AVPlayerLooper(player: localPlayer, templateItem: item)
        let owner = MiniAppNowPlayingOwner(id: lease.owner, players: [localPlayer])
        owner.session.nowPlayingInfoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "JibunKit Loop Tone",
            MPMediaItemPropertyArtist: "MediaAudioProbe", MPNowPlayingInfoPropertyPlaybackRate: 1.0]
        owner.installStandardHandlers({ [weak self, weak localPlayer] command in
            guard let self, self.playerLease == lease else { return false }
            switch command {
            case .play:
                do { try await self.coordinator.activateForUserAction(lease); localPlayer?.play() } catch { return false }
            case .pause: localPlayer?.pause(); try? self.coordinator.updateIntent(.stoppedByUser, for: lease)
            case .changePlaybackPosition(let seconds):
                guard let localPlayer, await localPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) else { return false }
            }
            self.playerCommandCount += 1; return true
        }, onCompletion: { [weak self] _, completed in self?.playerStatus = completed ? "remote操作完了" : "remote操作失敗" })
        player = localPlayer; looper = localLooper; nowPlaying = owner
        localPlayer.play(); _ = await owner.requestActivation()
    }
    private func rebuildPlayerAfterReset() async {
        guard let lease = playerLease else { return }
        let operation = playerOperation
        do {
            player?.pause(); try await nowPlaying?.invalidate(); nowPlaying = nil; looper = nil; player = nil
            guard playerOperation == operation, playerLease == lease else { return }
            try await coordinator.reactivate(lease)
            guard playerOperation == operation, playerLease == lease else { return }
            try await installPlayerNative(for: lease)
            guard playerOperation == operation, playerLease == lease else { return }
            playerStatus = "media reset再構築済み"
        } catch { playerError = "media reset再構築: \(error)"; playerStatus = "再構築失敗" }
    }
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
}
#endif
