#if os(iOS)
import AVFoundation
import JibunKitCore
import XCTest
@testable import JibunKit_App

@MainActor
final class MediaAudioNativeTests: XCTestCase {
    override func setUp() async throws { await MediaAudioProbe.state.reset() }
    override func tearDown() async throws { await MediaAudioProbe.state.reset() }

    func testAVPlayerNowPlayingAndOtherOwnerGenerationSurviveOneSideStop() async throws {
        let state = MediaAudioProbe.state
        await state.startPlayer()
        XCTAssertEqual(state.nowPlayingTitle, "JibunKit Loop Tone")
        for _ in 0..<50 where state.playerTime <= 0.1 { try await Task.sleep(for: .milliseconds(100)) }
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

    func testFeatureRecordingStartFailureReturnsItsLease() async {
        let coordinator = MiniAppAudioSessionCoordinator(driver: MediaAudioTestDriver())
        let backend = MediaAudioTestRecordingBackend(); backend.failStart = true
        let state = MediaAudioProbeState(coordinator: coordinator, permission: { true }, recording: backend)
        await state.startRecording(featureConsent: true)
        XCTAssertNil(state.recorderLease)
        XCTAssertTrue(coordinator.activeOwners.isEmpty)
        XCTAssertEqual(state.recorderStatus, "失敗")
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
        do { try coordinator.reactivate(stoppedLease); XCTFail("Stopped lease must not resume") }
        catch MiniAppAudioSessionCoordinator.Failure.unknownLease { }
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

        let failing = MediaAudioProbeState(coordinator: coordinator, permission: { true },
            recording: MediaAudioTestRecordingBackend(), beforePlayerStop: { throw MediaAudioStopFailure.expected })
        await failing.startPlayer(); await failing.stopPlayer()
        XCTAssertNotNil(failing.playerLease)
        XCTAssertEqual(failing.playerStatus, "停止失敗")
        XCTAssertEqual(coordinator.activeOwners, [MiniAppID("media-audio-player")])
    }

    func testProductionNativeOwnerIsConstructibleAndSharedForCaptureBridge() {
        XCTAssertTrue(MiniAppNativeAudio.coordinator === MiniAppNativeAudio.coordinator)
    }
}

@MainActor private final class MediaAudioTestDriver: MiniAppAudioSessionDriver {
    var activations: [Bool] = []
    func apply(_ profile: MiniAppAudioProfile) throws {}
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws { activations.append(active) }
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

private enum MediaAudioStopFailure: Error { case expected }
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
