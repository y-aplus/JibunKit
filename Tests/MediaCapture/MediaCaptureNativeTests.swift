import XCTest
@testable import JibunKit_App
import JibunKitCore
import UIKit
import VisionKit

@MainActor
final class MediaCaptureNativeTests: XCTestCase {
    func testProbePublishesTwoRealFeatureDefinitions() {
        let definitions = MediaCaptureProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("media-photo"), MiniAppID("media-scanner")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onSceneActivityChange != nil })
    }

    func testRealFeatureFactoryStopJoinsAndKeepsOtherValueAndGeneration() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permission = NativePermission()
        let defaults = try makeDefaults()
        let photo = PhotoFixture(coordinator: coordinator, permissions: permission,
                                 consentStore: allowed(defaults, owner: "media-photo", ids: ["camera"]))
        let scanner = ScannerFixture(coordinator: coordinator, permissions: permission,
                                     consentStore: allowed(defaults, owner: "media-scanner", ids: ["camera"]))
        let photoDefinition = photo.definition, scannerDefinition = scanner.definition
        try await photoDefinition.lifetime?.start()
        try await scannerDefinition.lifetime?.start()
        activate(MiniAppID("media-photo")) { photoDefinition.onSceneActivityChange?($0) }
        activate(MiniAppID("media-scanner")) { scannerDefinition.onSceneActivityChange?($0) }
        scanner.state.retainedValue = 41
        let scannerRuntime = try XCTUnwrap(scannerDefinition.lifetime?.runtime)
        let scannerGeneration = scanner.state.generation
        let stopGate = NativeGate()
        try await photo.owner.start(.init(resources: [.camera]) { { _ in await stopGate.wait() } })

        let stopping = Task { @MainActor in await photoDefinition.lifetime?.stop() }
        await stopGate.waitUntilEntered()
        XCTAssertTrue(scannerDefinition.lifetime?.runtime === scannerRuntime)
        XCTAssertEqual(scanner.state.retainedValue, 41)
        stopGate.open()
        await stopping.value

        XCTAssertTrue(scannerDefinition.lifetime?.runtime === scannerRuntime)
        XCTAssertFalse(scannerRuntime.isClosed)
        XCTAssertEqual(scanner.state.retainedValue, 41)
        XCTAssertEqual(scanner.state.generation, scannerGeneration)
        await scannerDefinition.lifetime?.stop()
    }

    func testRealFeatureConsentDenialPrecedesOSPermissionAndNativeStart() async throws {
        let permission = NativePermission()
        let fixture = PhotoFixture(coordinator: .init(), permissions: permission, consentStore: nil)
        let definition = fixture.definition
        try await definition.lifetime?.start()
        activate(MiniAppID("media-photo")) { definition.onSceneActivityChange?($0) }
        var started = false
        await XCTAssertThrowsErrorAsync(try await fixture.owner.start(.init(resources: [.camera]) {
            started = true
            return { _ in }
        })) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .featureConsentDenied(.camera))
        }
        XCTAssertTrue(permission.requested.isEmpty)
        XCTAssertFalse(started)
        await definition.lifetime?.stop()
    }

    func testPhotoFeatureCaptureFailureStopsAndReleasesCamera() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let defaults = try makeDefaults()
        let fixture = PhotoFixture(
            coordinator: coordinator, permissions: NativePermission(),
            consentStore: allowed(defaults, owner: "media-photo", ids: ["camera"]),
            photoCapture: { owner in
                try await owner.start(.init(resources: [.camera]) { { _ in } })
                throw MiniAppCaptureFailure.native("injected photo failure")
            }
        )
        let definition = fixture.definition
        try await definition.lifetime?.start()
        activate(MiniAppID("media-photo")) { definition.onSceneActivityChange?($0) }
        await fixture.takePhoto()
        XCTAssertNil(coordinator.currentCameraOwner)
        XCTAssertEqual(fixture.owner.state, .idle)
        XCTAssertTrue(fixture.state.status.contains("injected photo failure"))
        await definition.lifetime?.stop()
    }

    func testRejectedAudioMovieDoesNotRetainProducerOrResult() async throws {
        let previous = MediaCaptureProbe.makeAcquireAudio
        defer { MediaCaptureProbe.makeAcquireAudio = previous }
        MediaCaptureProbe.makeAcquireAudio = { _, _ in
            { return { } }
        }
        let fixture = PhotoFixture(coordinator: .init(), permissions: NativePermission(), consentStore: nil)
        let definition = fixture.definition
        try await definition.lifetime?.start()
        activate(MiniAppID("media-photo")) { definition.onSceneActivityChange?($0) }
        await fixture.recordAudioMovie()
        XCTAssertFalse(fixture.hasActiveMovieProducer)
        XCTAssertNil(fixture.state.movieURL)
        XCTAssertEqual(fixture.state.resultCount, 0)
        XCTAssertTrue(fixture.state.status.contains("featureConsentDenied"))
        await definition.lifetime?.stop()
    }

    func testInjectedRealScannerFeatureJoinsOwnedPresentationStop() async throws {
        let defaults = try makeDefaults()
        let events = NativeEvents()
        let fixture = ScannerFixture(
            coordinator: .init(), permissions: NativePermission(),
            consentStore: allowed(defaults, owner: "media-scanner", ids: ["camera"]),
            documentOperation: { _, _ in
                .init(resources: [.camera]) {
                    events.values.append("present")
                    return { _ in events.values.append("dismiss") }
                }
            }
        )
        let definition = fixture.definition
        try await definition.lifetime?.start()
        activate(MiniAppID("media-scanner")) { definition.onSceneActivityChange?($0) }
        await fixture.scanDocument()
        XCTAssertEqual(events.values, ["present"])
        await fixture.stop()
        XCTAssertEqual(events.values, ["present", "dismiss"])
        XCTAssertEqual(fixture.owner.state, .idle)
        await definition.lifetime?.stop()
    }

    func testVisionAdapterRejectsOldControllerAndExternalDismissReleasesOnlyItsPresentation() {
        // Keep XCTest's async error observer out of this SDK/delegate exercise.
        // The same assertions run in an explicit main-actor task; errors remain failures.
        let finished = expectation(description: "Vision ownership scenario finished")
        Task { @MainActor in
            do { try await self.exerciseVisionPresentationOwnership() }
            catch { XCTFail("Vision ownership scenario: \(error)") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)
    }

    private func exerciseVisionPresentationOwnership() async throws {
        print("VISION-PHASE setup")
        let coordinator = MiniAppCaptureCoordinator()
        let ownerID = MiniAppID("vision-test")
        let owner = MiniAppCaptureOwner(id: ownerID, coordinator: coordinator,
                                        permissions: NativePermission(), consent: { _ in true })
        let runtime = MiniAppRuntime()
        let presentations = MiniAppPresentationOwner(id: ownerID)
        try presentations.connect(to: runtime)
        try owner.connect(to: runtime)
        activate(ownerID) { owner.receive($0) }
        let harness = PresentationHarness()
        let adapter = MiniAppVisionCaptureAdapter(
            presentationOwner: presentations,
            present: { harness.presented = $0 },
            dismiss: { controller in
                XCTAssertTrue(harness.presented === controller)
                harness.dismissed.append(controller)
                harness.presented = nil
            },
            documentSupported: { true },
            makeDocumentController: { VNDocumentCameraViewController() }
        )
        var firstResults = 0
        try await owner.start(adapter.documentOperation(result: { _ in firstResults += 1 },
                                                         ended: { await owner.stop() }))
        let first = try XCTUnwrap(harness.presented as? VNDocumentCameraViewController)
        print("VISION-PHASE first-cancel")
        adapter.documentCameraViewControllerDidCancel(first)
        await eventually { coordinator.currentCameraOwner == nil }

        print("VISION-PHASE second-start")
        var secondResults = 0
        try await owner.start(adapter.documentOperation(result: { _ in secondResults += 1 },
                                                         ended: { await owner.stop() }))
        let second = try XCTUnwrap(harness.presented as? VNDocumentCameraViewController)
        adapter.documentCameraViewControllerDidCancel(first)
        await Task.yield()
        XCTAssertEqual(firstResults, 1)
        XCTAssertEqual(secondResults, 0)
        XCTAssertEqual(owner.state, .running([.camera]))

        let otherOwner = MiniAppPresentationOwner(id: MiniAppID("other-presentation"))
        let otherRuntime = MiniAppRuntime()
        try otherOwner.connect(to: otherRuntime)
        var otherDismissed = false
        _ = try otherOwner.begin(.uiViewController) { otherDismissed = true }
        print("VISION-PHASE external-dismiss")
        let presentation = UIPresentationController(presentedViewController: second, presenting: nil)
        adapter.presentationControllerDidDismiss(presentation)
        await eventually { coordinator.currentCameraOwner == nil }
        XCTAssertEqual(secondResults, 1)
        XCTAssertFalse(otherDismissed)
        XCTAssertEqual(harness.dismissed.count, 1)

        print("VISION-PHASE navigation-start")
        try await owner.start(adapter.documentOperation(result: { _ in },
                                                         ended: { await owner.stop() }))
        let third = try XCTUnwrap(harness.presented)
        print("VISION-PHASE navigation-dismiss")
        await presentations.dismissForNavigation()
        await eventually { coordinator.currentCameraOwner == nil }
        XCTAssertTrue(harness.dismissed.last === third)
        XCTAssertFalse(otherDismissed)
        await runtime.shutdown()
        await otherRuntime.shutdown()
        print("VISION-PHASE completed")
    }

    func testDataScannerStartFailureDismissesAndReleasesReservation() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let id = MiniAppID("scanner-failure")
        let owner = MiniAppCaptureOwner(id: id, coordinator: coordinator,
                                        permissions: NativePermission(), consent: { _ in true })
        let runtime = MiniAppRuntime()
        let presentations = MiniAppPresentationOwner(id: id)
        try presentations.connect(to: runtime)
        try owner.connect(to: runtime)
        activate(id) { owner.receive($0) }
        let harness = PresentationHarness()
        let adapter = MiniAppVisionCaptureAdapter(
            presentationOwner: presentations,
            present: { harness.presented = $0 },
            dismiss: { controller in harness.dismissed.append(controller); harness.presented = nil },
            dataScannerSupported: { true }, dataScannerAvailable: { true },
            startDataScanner: { _ in throw MiniAppCaptureFailure.native("injected start failure") }
        )
        await XCTAssertThrowsErrorAsync(try await owner.start(adapter.codeOperation(
            result: { _ in }, ended: { await owner.stop() }
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("injected start failure"))
        }
        XCTAssertNil(coordinator.currentCameraOwner)
        XCTAssertEqual(presentations.activePresentationCount, 0)
        XCTAssertEqual(harness.dismissed.count, 1)
        await runtime.shutdown()
    }

    func testCameraAndMicrophoneDeclarationsRemainDistinct() {
        let photo = MediaCaptureProbe.definitions[0]
        XCTAssertEqual(Set(photo.permissions.map(\.id)), ["camera", "microphone"])
        XCTAssertEqual(MediaCaptureProbe.definitions[1].permissions.map(\.id), ["camera"])
    }

    func testMovieFailureIsNotCountedAndRemovesTemporaryFile() throws {
        let fixture = PhotoFixture(coordinator: .init(), permissions: NativePermission())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-capture-failed-\(UUID().uuidString).mov")
        try Data("partial".utf8).write(to: url)
        fixture.applyMovieCompletion(.failed(url, "injected"))
        XCTAssertEqual(fixture.state.resultCount, 0)
        XCTAssertNil(fixture.state.movieURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "MediaCaptureNativeTests.\(UUID().uuidString)"))
    }

    private func allowed(_ defaults: UserDefaults, owner: String, ids: [String]) -> MiniAppConsentStore {
        let store = MiniAppConsentStore(defaults: defaults)
        for id in ids { store.setConsent(.allowed, for: MiniAppID(owner), permissionID: id) }
        return store
    }
}

@MainActor
private final class NativePermission: MiniAppCapturePermissionClient {
    private(set) var requested: [MiniAppCaptureResource] = []
    func request(_ resource: MiniAppCaptureResource) async -> Bool {
        requested.append(resource)
        return true
    }
}

@MainActor
private final class NativeGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func waitUntilEntered() async { while !entered { await Task.yield() } }
    func open() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class PresentationHarness {
    var presented: UIViewController?
    var dismissed: [UIViewController] = []
}

@MainActor private final class NativeEvents { var values: [String] = [] }

@MainActor
private func activate(_ owner: MiniAppID,
                      handler: @escaping @MainActor (MiniAppSceneActivity) -> Void) {
    let dispatcher = MiniAppSceneActivityDispatcher(handlers: [.init(id: owner, handler: handler)])
    dispatcher.connect(phase: .active, selectedID: owner)
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
    XCTAssertTrue(condition())
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do { _ = try await expression(); XCTFail("expected error") }
    catch { handler(error) }
}
