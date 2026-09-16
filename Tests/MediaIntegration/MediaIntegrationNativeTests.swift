import XCTest
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class MediaIntegrationNativeTests: XCTestCase {
    func testVideoSharesAcceptedAudioProfileAndReleasesOnlyItself() async throws {
        let audio = MiniAppAudioSessionCoordinator(driver: IntegrationAudioDriver())
        let compatible = MiniAppAudioProfile(category: .playAndRecord, mode: .spokenAudio)
        let stops = IntegrationStops()
        let first = try await audio.acquire(owner: MiniAppID("player"), request: .init(
            acceptableProfiles: [.init(category: .playback, mode: .spokenAudio), compatible], purpose: "player"),
            stop: { stops.player += 1 }, receive: { _ in })
        guard case .acquired(let player) = first else { return XCTFail("Player rejected") }
        let bridge = MediaCaptureAudioBridge(audio: audio)
        let release = try await bridge.acquire(owner: MiniAppID("video"), stopNativeOnly: { stops.video += 1 },
                                              released: { stops.released += 1 })
        XCTAssertEqual(audio.activeProfile, compatible)
        XCTAssertEqual(audio.activeOwners, [MiniAppID("player"), MiniAppID("video")])
        await release()
        XCTAssertEqual(stops.video, 1)
        XCTAssertEqual(stops.released, 1)
        XCTAssertEqual(stops.player, 0)
        XCTAssertEqual(audio.activeOwners, [player.owner])
        try await audio.release(player)
    }

    func testIncompatibleVideoRequiresExplicitOneShotReplacement() async throws {
        let audio = MiniAppAudioSessionCoordinator(driver: IntegrationAudioDriver())
        let stops = IntegrationStops()
        _ = try await audio.acquire(owner: MiniAppID("exclusive"), request: .init(
            acceptableProfiles: [.init(category: .record, mode: .measurement)], purpose: "exclusive"),
            stop: { stops.player += 1 }, receive: { _ in })
        let bridge = MediaCaptureAudioBridge(audio: audio)
        do {
            _ = try await bridge.acquire(owner: MiniAppID("video"), stopNativeOnly: {}, released: {})
            XCTFail("Conflict must not silently stop the other Feature")
        } catch MediaCaptureAudioBridge.Failure.conflict { }
        XCTAssertEqual(stops.player, 0)
        bridge.replaceOnNextRequest = true
        let release = try await bridge.acquire(owner: MiniAppID("video"), stopNativeOnly: {}, released: {})
        XCTAssertEqual(stops.player, 1)
        XCTAssertFalse(bridge.replaceOnNextRequest)
        await release()
        XCTAssertTrue(audio.activeOwners.isEmpty)
    }
}

@MainActor private final class IntegrationAudioDriver: MiniAppAudioSessionDriver {
    func apply(_ profile: MiniAppAudioProfile) throws {}
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {}
}
@MainActor private final class IntegrationStops {
    var player = 0
    var video = 0
    var released = 0
}
