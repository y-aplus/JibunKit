import XCTest
@testable import JibunKit_App
import JibunKitCore

@MainActor
final class MediaCaptureNativeTests: XCTestCase {
    func testProbePublishesTwoRealFeatureDefinitions() {
        let definitions = MediaCaptureProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("media-photo"), MiniAppID("media-scanner")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onSceneActivityChange != nil })
    }

    func testStoppingOneFeatureKeepsOtherNonInitialValueAndRuntimeGeneration() async throws {
        let definitions = MediaCaptureProbe.definitions
        let photo = try XCTUnwrap(definitions[0].lifetime)
        let scanner = try XCTUnwrap(definitions[1].lifetime)
        try await photo.start()
        try await scanner.start()
        let scannerRuntime = try XCTUnwrap(scanner.runtime)
        MediaCaptureFixtures.scanner.state.retainedValue = 41
        let scannerGeneration = MediaCaptureFixtures.scanner.state.generation

        await photo.stop()

        XCTAssertTrue(scanner.runtime === scannerRuntime)
        XCTAssertFalse(scannerRuntime.isClosed)
        XCTAssertEqual(MediaCaptureFixtures.scanner.state.retainedValue, 41)
        XCTAssertEqual(MediaCaptureFixtures.scanner.state.generation, scannerGeneration)
        await scanner.stop()
    }

    func testCameraOnlyAndMicrophoneDeclarationsRemainDistinct() {
        let photo = MediaCaptureProbe.definitions[0]
        XCTAssertEqual(Set(photo.permissions.map(\.id)), ["camera", "microphone"])
        let scanner = MediaCaptureProbe.definitions[1]
        XCTAssertEqual(scanner.permissions.map(\.id), ["camera"])
    }
}
