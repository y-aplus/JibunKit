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
        XCTAssertEqual(state.nowPlayingTitle, "JibunKit Local Tone")
        for _ in 0..<50 where state.playerTime <= 0.1 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThan(state.playerTime, 0.1, state.errorText)

        try await state.reserveRecorderAudio()
        let recorderGeneration = try XCTUnwrap(state.recorderLease?.generation)
        XCTAssertEqual(state.coordinator.activeOwners.count, 2)
        await state.stopPlayer()

        XCTAssertEqual(state.coordinator.activeOwners, [MiniAppID("media-audio-recorder")])
        XCTAssertEqual(state.recorderLease?.generation, recorderGeneration)
        XCTAssertEqual(state.recorderGeneration, recorderGeneration)
        XCTAssertEqual(state.coordinator.activeProfile,
                       MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio))
    }

    func testRealMicrophoneRecordAndPlaybackWhenPermissionIsGranted() async throws {
        let state = MediaAudioProbe.state
        state.setMicrophoneConsent(true)
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw XCTSkip("Grant microphone permission in the signed diagnostic host before this device test")
        }
        await state.startRecording()
        XCTAssertEqual(state.status, "録音中", state.errorText)
        try await Task.sleep(for: .milliseconds(500))
        await state.stopRecordingAndPlay()
        XCTAssertGreaterThan(state.recorderSampleCount, 0, state.errorText)
        XCTAssertTrue(state.status.hasPrefix("録音再生中"), state.errorText)
    }
}
#endif
