#if os(iOS)
import AVFoundation
@_spi(Testing) import JibunKitCore
import XCTest
@testable import JibunKit_App

@MainActor
final class MediaAudioNativeTests: XCTestCase {
    override func setUp() async throws { await MediaAudioProbe.state.reset() }
    override func tearDown() async throws { await MediaAudioProbe.state.reset() }

    func testProfileConvenienceConstantsMatchCurrentAVAudioSessionSDK() {
        XCTAssertEqual(MiniAppAudioProfile.Category.playback.rawValue, AVAudioSession.Category.playback.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Category.playAndRecord.rawValue, AVAudioSession.Category.playAndRecord.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Category.ambient.rawValue, AVAudioSession.Category.ambient.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Category.soloAmbient.rawValue, AVAudioSession.Category.soloAmbient.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Category.record.rawValue, AVAudioSession.Category.record.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Category.multiRoute.rawValue, AVAudioSession.Category.multiRoute.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.spokenAudio.rawValue, AVAudioSession.Mode.spokenAudio.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.measurement.rawValue, AVAudioSession.Mode.measurement.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.default.rawValue, AVAudioSession.Mode.default.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.voiceChat.rawValue, AVAudioSession.Mode.voiceChat.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.gameChat.rawValue, AVAudioSession.Mode.gameChat.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.videoRecording.rawValue, AVAudioSession.Mode.videoRecording.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.moviePlayback.rawValue, AVAudioSession.Mode.moviePlayback.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Mode.videoChat.rawValue, AVAudioSession.Mode.videoChat.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.RouteSharingPolicy.default.rawValue, AVAudioSession.RouteSharingPolicy.default.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.RouteSharingPolicy.longFormAudio.rawValue, AVAudioSession.RouteSharingPolicy.longFormAudio.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.RouteSharingPolicy.independent.rawValue, AVAudioSession.RouteSharingPolicy.independent.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.RouteSharingPolicy.longFormVideo.rawValue, AVAudioSession.RouteSharingPolicy.longFormVideo.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.mixWithOthers.rawValue, AVAudioSession.CategoryOptions.mixWithOthers.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.duckOthers.rawValue, AVAudioSession.CategoryOptions.duckOthers.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.interruptSpokenAudioAndMixWithOthers.rawValue,
                       AVAudioSession.CategoryOptions.interruptSpokenAudioAndMixWithOthers.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.allowBluetoothHFP.rawValue, AVAudioSession.CategoryOptions.allowBluetoothHFP.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.allowBluetoothA2DP.rawValue, AVAudioSession.CategoryOptions.allowBluetoothA2DP.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.allowAirPlay.rawValue, AVAudioSession.CategoryOptions.allowAirPlay.rawValue)
        XCTAssertEqual(MiniAppAudioProfile.Options.defaultToSpeaker.rawValue, AVAudioSession.CategoryOptions.defaultToSpeaker.rawValue)
    }

    func testAVPlayerNowPlayingAndOtherOwnerGenerationSurviveOneSideStop() async throws {
        let state = MediaAudioProbe.state
        await state.startPlayer()
        XCTAssertEqual(state.nowPlayingTitle, "JibunKit Loop Tone")
        for _ in 0..<50 {
            let time = state.playerTime
            if time.isFinite && time > 0.1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(state.playerTime, 0.1, state.playerError)
        try await state.reserveRecorderAudio()
        let generation = try XCTUnwrap(state.recorderLease?.generation)
        await state.stopPlayer()
        XCTAssertEqual(state.coordinator.activeOwners, [MiniAppID("media-audio-recorder")])
        XCTAssertEqual(state.recorderLease?.generation, generation)
        XCTAssertEqual(state.recorderGeneration, generation)
        XCTAssertEqual(state.coordinator.activeProfile, .init(category: .playAndRecord, mode: .spokenAudio))
    }

    func testFeatureConnectionRejectsLatePermissionAndStartsNothing() async throws {
        let driver = MediaAudioTestDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let permission = MediaAudioPermissionGate()
        let backend = MediaAudioTestRecordingBackend()
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { await permission.wait() }, recording: backend)
        let starting = Task { @MainActor in await state.startRecording(featureConsent: true) }
        await permission.waitUntilRequested()
        await state.releaseRecorder() // invalidates the pending Feature operation even before a lease exists
        permission.resolve(true)
        await starting.value
        XCTAssertNil(state.recorderLease)
        XCTAssertEqual(backend.startCount, 0)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    func testFeatureConnectionRejectsConsentChangeWhilePermissionIsPending() async {
        let coordinator = MiniAppAudioSessionCoordinator(driver: MediaAudioTestDriver())
        let permission = MediaAudioPermissionGate()
        let backend = MediaAudioTestRecordingBackend()
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { await permission.wait() }, recording: backend)
        let starting = Task { @MainActor in await state.startRecording(featureConsent: true) }
        await permission.waitUntilRequested()
        state.updateFeatureConsent(false)
        permission.resolve(true); await starting.value
        XCTAssertNil(state.recorderLease)
        XCTAssertEqual(backend.startCount, 0)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    func testFeatureRecordingStartFailureReturnsItsLease() async {
        let coordinator = MiniAppAudioSessionCoordinator(driver: MediaAudioTestDriver())
        let backend = MediaAudioTestRecordingBackend(); backend.failStart = true
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: backend)
        await state.startRecording(featureConsent: true)
        XCTAssertNil(state.recorderLease)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(state.recorderStatus, "失敗")
    }

    func testConflictConfirmationWithoutCurrentConsentDoesNotStopIncumbent() async throws {
        let coordinator = MiniAppAudioSessionCoordinator(driver: MediaAudioTestDriver())
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: MediaAudioTestRecordingBackend())
        let incumbent = try await coordinator.acquire(owner: MiniAppID("exclusive"),
            request: .init(acceptableProfiles: [.init(category: .record, mode: .measurement)], purpose: "exclusive"),
            stop: { XCTFail("Consent rejection must not stop the incumbent") }, receive: { _ in })
        guard case .acquired = incumbent else { return XCTFail("Incumbent missing") }
        await state.startRecording(featureConsent: true)
        XCTAssertNil(state.recorderLease)
        XCTAssertTrue(state.recorderStatus.contains("競合"))
        await state.confirmRecorderReplacement(featureConsent: false)
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("exclusive")])
        XCTAssertNil(state.recorderLease)
    }

    func testRealFeatureLifetimeStopKeepsOtherRuntimeAndLease() async throws {
        let definitions = MediaAudioProbe.definitions
        let player = try XCTUnwrap(definitions[0].lifetime)
        let recorder = try XCTUnwrap(definitions[1].lifetime)
        try await player.start(); try await recorder.start()
        let otherRuntime = try XCTUnwrap(recorder.runtime)
        let state = MediaAudioProbe.state
        await state.startPlayer()
        XCTAssertNotNil(state.playerLease)
        try await state.reserveRecorderAudio()
        let otherLease = try XCTUnwrap(state.recorderLease)
        await player.stop()
        XCTAssertNil(state.playerLease)
        XCTAssertTrue(recorder.runtime === otherRuntime)
        XCTAssertEqual(state.recorderLease, otherLease)
        XCTAssertEqual(state.coordinator.activeOwners, [otherLease.owner])
        await recorder.stop()
        XCTAssertTrue(state.coordinator.activeOwners.isEmpty)
    }

    func testFeatureConnectionReactivatesAfterInterruptionButNotAfterUserStop() async throws {
        let driver = MediaAudioTestDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: MediaAudioTestRecordingBackend())
        await state.startPlayer()
        coordinator.receiveInterruptionBegan(); coordinator.receiveInterruptionEnded(shouldResume: true)
        await state.startPlayer()
        XCTAssertEqual(Array(driver.activations.suffix(1)), [true])
        let stoppedLease = try XCTUnwrap(state.playerLease)
        await state.stopPlayer()
        do { try await coordinator.reactivate(stoppedLease); XCTFail("Stopped lease must not resume") }
        catch MiniAppAudioSessionCoordinator.Failure.resumeNotAllowed { }
    }

    func testFeatureStopWaitsAndStopFailureRetainsLease() async throws {
        let driver = MediaAudioTestDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let gate = MediaAudioStopGate()
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true },
            recording: MediaAudioTestRecordingBackend(), beforePlayerStop: { try await gate.wait() })
        await state.startPlayer()
        let stopping = Task { @MainActor in await state.stopPlayer() }
        await gate.waitUntilEntered()
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("media-audio-player")])
        gate.finish(.success(())); await stopping.value
        XCTAssertTrue(coordinator.activeOwners.isEmpty)

        let failure = MediaAudioStopFailureSwitch()
        let failing = MediaAudioProbeState(coordinator: coordinator, permission: { true },
            recording: MediaAudioTestRecordingBackend(), beforePlayerStop: { try failure.check() })
        await failing.startPlayer(); await failing.stopPlayer()
        XCTAssertNotNil(failing.playerLease)
        XCTAssertEqual(failing.playerStatus, "停止失敗")
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("media-audio-player")])
        failure.shouldFail = false
        await failing.stopPlayer()
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
    }

    func testProductionNativeOwnerIsConstructibleAndSharedForCaptureBridge() {
        XCTAssertTrue(MiniAppNativeAudio.coordinator === MiniAppNativeAudio.coordinator)
    }

    func testNowPlayingRejectsRecursiveInvalidationFromRunningHandler() async throws {
        let player = AVPlayer(url: FileManager.default.temporaryDirectory.appendingPathComponent("absent"))
        let owner = MiniAppNowPlayingOwner(id: MiniAppID("recursive-now-playing"), players: [player])
        let result = MediaAudioNowPlayingFailureBox()
        _ = await owner.deliverForTesting(.play) { _ in
            do { try await owner.invalidate() }
            catch let failure as MiniAppNowPlayingOwner.Failure { result.failure = failure }
            catch { XCTFail("Unexpected invalidation error: \(error)") }
            return false
        }
        XCTAssertEqual(result.failure, .recursiveInvalidation)
        try await owner.invalidate()
    }

    func testFeatureCanRecoverInitialActivationFailureAndRetry() async throws {
        let driver = MediaAudioTestDriver(); driver.failNextActivation = true
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: MediaAudioTestRecordingBackend())
        await state.startPlayer()
        XCTAssertNil(state.playerLease)
        guard case .recoveryFailed = coordinator.sessionState else { return XCTFail("Expected recovery state") }
        await state.recoverAudioSession()
        XCTAssertEqual(coordinator.sessionState, .inactive)
        await state.startPlayer()
        XCTAssertNotNil(state.playerLease)
        await state.stopPlayer()
    }

    func testFeatureRollbackFailureRequiresRecoveryBeforeFurtherAdmission() async throws {
        let driver = MediaAudioTestDriver()
        let coordinator = MiniAppAudioSessionCoordinator(driver: driver)
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: MediaAudioTestRecordingBackend())
        await state.startPlayer()
        driver.failApplyCount = 2
        do { try await state.reserveRecorderAudio(); XCTFail("Expected profile and rollback failure") } catch { }
        guard case .recoveryFailed = coordinator.sessionState else { return XCTFail("Expected recovery failure") }
        await state.recoverAudioSession()
        guard case .active = coordinator.sessionState else { return XCTFail("Recovery did not restore active profile") }
        await state.stopPlayer()
    }
}

@MainActor private final class MediaAudioTestDriver: MiniAppAudioSessionDriver {
    var activations: [Bool] = []
    var failApplyCount = 0
    var failNextActivation = false
    func apply(_ profile: MiniAppAudioProfile) throws {
        if failApplyCount > 0 { failApplyCount -= 1; throw MediaAudioStopFailure.expected }
    }
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        if active, failNextActivation { failNextActivation = false; throw MediaAudioStopFailure.expected }
        activations.append(active)
    }
}

@MainActor private final class MediaAudioTestRecordingBackend: MediaAudioRecordingBackend {
    var startCount = 0
    var failStart = false
    func start(at url: URL) throws { startCount += 1; if failStart { throw MediaAudioStopFailure.expected } }
    func stopAndPlay(at url: URL) throws -> AVAudioFramePosition { 8_000 }
    func stop() {}
}

@MainActor private final class MediaAudioPermissionGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    func wait() async -> Bool {
        requested = true; requestWaiters.forEach { $0.resume() }; requestWaiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }
    func resolve(_ value: Bool) { continuation?.resume(returning: value); continuation = nil }
}
@MainActor private final class MediaAudioNowPlayingFailureBox { var failure: MiniAppNowPlayingOwner.Failure? }

private enum MediaAudioStopFailure: Error { case expected }
@MainActor private final class MediaAudioStopFailureSwitch {
    var shouldFail = true
    func check() throws { if shouldFail { throw MediaAudioStopFailure.expected } }
}
@MainActor private final class MediaAudioStopGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async throws {
        entered = true; waiters.forEach { $0.resume() }; waiters.removeAll()
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish(_ result: Result<Void, Error>) { continuation?.resume(with: result); continuation = nil }
}
#endif
