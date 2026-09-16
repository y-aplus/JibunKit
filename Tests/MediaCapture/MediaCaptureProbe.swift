import AVFoundation
import JibunKitCore
import SwiftUI
import UIKit

@MainActor
enum MediaCaptureProbe {
    /// Parent assigns the P2-1 coordinator bridge before opening the fixture.
    static var acquireAudio: MiniAppCaptureOperation.AcquireAudio?
    static var definitions: [MiniAppDefinition] {
        [MediaCaptureFixtures.photo.definition, MediaCaptureFixtures.scanner.definition]
    }
}

@MainActor
enum MediaCaptureFixtures {
    static let coordinator = MiniAppCaptureCoordinator.shared
    static let photo = PhotoFixture(coordinator: coordinator)
    static let scanner = ScannerFixture(coordinator: coordinator)
}

@MainActor
final class MediaCaptureFixtureState: ObservableObject {
    @Published var status = "準備前"
    @Published var resultCount = 0
    @Published var retainedValue = 0
    @Published var generation = 0
}

@MainActor
final class PhotoFixture {
    let id = MiniAppID("media-photo")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.owner.connect(to: runtime)
        self.state.generation += 1
        self.state.status = "写真: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator) {
        owner = MiniAppCaptureOwner(id: id, coordinator: coordinator,
                                    permissions: MiniAppAVCapturePermissionClient())
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: "撮影Probe", systemImage: "camera",
            lifetime: lifetime,
            permissions: [
                .init(id: "camera", title: "カメラ", purpose: "写真と動画を撮影します", deniedBehavior: "撮影を開始しません"),
                .init(id: "microphone", title: "マイク", purpose: "動画へ音声を収録します", deniedBehavior: "音声付き動画を開始しません"),
            ],
            onSceneActivityChange: { [weak self] in self?.owner.receive($0) }
        ) { [weak self] _ in
            PhotoProbeView(fixture: self!)
        }
    }

    func takePhoto() async {
        let producer = MiniAppAVCaptureSessionProducer(mode: .photo)
        let operation = MiniAppCaptureOperation(resources: [.camera]) { [weak self] in
            try await producer.start()
            self?.state.status = "写真: camera実行中"
            return { _ in await producer.stop() }
        }
        do {
            try await owner.start(operation, switching: .stopCurrent)
            let data = try await producer.capturePhoto()
            // Fixture/Feature owns the result bytes; Core never stores them.
            state.resultCount += data.isEmpty ? 0 : 1
            state.retainedValue += 1
            state.status = "写真成功 \(state.resultCount)件"
            await owner.stop()
        } catch {
            state.status = "写真失敗: \(error)"
        }
    }

    func recordAudioMovie() async {
        guard let acquireAudio = MediaCaptureProbe.acquireAudio else {
            state.status = "音声付き動画: Audio接続未統合"
            return
        }
        let producer = MiniAppAVCaptureSessionProducer(mode: .movie, includesAudio: true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-capture-\(UUID().uuidString).mov")
        let operation = MiniAppCaptureOperation(
            resources: [.camera, .microphone], acquireAudio: acquireAudio,
            startNative: { [weak self] in
                try await producer.start()
                try await producer.startMovie(to: url)
                self?.state.status = "音声付き動画: 録画中"
                return { _ in await producer.stop() }
            }
        )
        do {
            try await owner.start(operation, switching: .stopCurrent)
            // The fixture Feature owns the destination URL and its later move/removal.
            state.retainedValue = url.path.count
        } catch { state.status = "音声付き動画失敗: \(error)" }
    }

    func stop() async {
        await owner.stop()
        state.resultCount += state.status.contains("録画中") ? 1 : 0
        state.status = "撮影停止・camera解放"
    }
}

@MainActor
final class ScannerFixture {
    let id = MiniAppID("media-scanner")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    let presentations: MiniAppPresentationOwner
    private var adapter: MiniAppVisionCaptureAdapter?
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        // Runtime cleanup is reverse registration order: capture native stop and
        // adapter dismissal run before the presentation owner's final sweep.
        try self.presentations.connect(to: runtime)
        try self.owner.connect(to: runtime)
        self.adapter = MiniAppVisionCaptureAdapter(
            presentationOwner: self.presentations,
            present: { controller in try await MediaCapturePresenter.present(controller) },
            dismiss: { await MediaCapturePresenter.dismiss() }
        )
        self.state.generation += 1
        self.state.status = "scan: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator) {
        owner = MiniAppCaptureOwner(id: id, coordinator: coordinator,
                                    permissions: MiniAppAVCapturePermissionClient())
        presentations = MiniAppPresentationOwner(id: id)
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: "Scan Probe", systemImage: "doc.viewfinder",
            lifetime: lifetime, presentations: presentations,
            permissions: [
                .init(id: "camera", title: "カメラ", purpose: "文書とコードを読み取ります", deniedBehavior: "scanを開始しません"),
            ],
            onSceneActivityChange: { [weak self] in self?.owner.receive($0) }
        ) { [weak self] _ in
            ScannerProbeView(fixture: self!)
        }
    }

    func scanDocument() async {
        guard let adapter else { state.status = "文書scan: 未接続"; return }
        do {
            try await owner.start(adapter.documentOperation(result: { [weak self] result in
                switch result {
                case .success(let pages):
                    self?.state.resultCount += pages.count
                    self?.state.retainedValue += pages.count
                    self?.state.status = "文書成功 \(pages.count)ページ"
                case .failure(let error): self?.state.status = "文書取消/失敗: \(error)"
                }
            }, ended: { [weak self] in await self?.owner.stop() }), switching: .stopCurrent)
        } catch { state.status = "文書開始失敗: \(error)" }
    }

    func scanCode() async {
        guard let adapter else { state.status = "code scan: 未接続"; return }
        do {
            try await owner.start(adapter.codeOperation(result: { [weak self] code in
                self?.state.resultCount += 1
                self?.state.retainedValue = code.count
                self?.state.status = "code成功: \(code)"
            }, ended: { [weak self] in await self?.owner.stop() }), switching: .stopCurrent)
        } catch { state.status = "code開始失敗: \(error)" }
    }

    func stop() async {
        await owner.stop()
        state.status = "scan停止・camera解放"
    }
}

private struct PhotoProbeView: View {
    @ObservedObject var state: MediaCaptureFixtureState
    let fixture: PhotoFixture
    init(fixture: PhotoFixture) { self.fixture = fixture; state = fixture.state }
    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("media.photo.status")
            Text("成果 \(state.resultCount) / 保持 \(state.retainedValue) / 世代 \(state.generation)")
            Button("実写真を撮る") { Task { await fixture.takePhoto() } }
            Button("音声付き動画") { Task { await fixture.recordAudioMovie() } }
            Button("停止") { Task { await fixture.stop() } }
        }
    }
}

private struct ScannerProbeView: View {
    @ObservedObject var state: MediaCaptureFixtureState
    let fixture: ScannerFixture
    init(fixture: ScannerFixture) { self.fixture = fixture; state = fixture.state }
    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("media.scanner.status")
            Text("成果 \(state.resultCount) / 保持 \(state.retainedValue) / 世代 \(state.generation)")
            Button("文書scanner") { Task { await fixture.scanDocument() } }
            Button("code scanner") { Task { await fixture.scanCode() } }
            Button("停止") { Task { await fixture.stop() } }
        }
    }
}

@MainActor
private enum MediaCapturePresenter {
    static func present(_ controller: UIViewController) async throws {
        guard let root = rootViewController() else { throw MiniAppCaptureFailure.unavailable("presenter") }
        await withCheckedContinuation { continuation in
            root.present(controller, animated: true) { continuation.resume() }
        }
    }
    static func dismiss() async {
        guard let root = rootViewController(), root.presentedViewController != nil else { return }
        await withCheckedContinuation { continuation in
            root.dismiss(animated: true) { continuation.resume() }
        }
    }
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    }
}
