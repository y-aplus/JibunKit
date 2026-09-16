import AVFoundation
import AVKit
import JibunKitCore
import SwiftUI
import UIKit

@MainActor
enum MediaCaptureProbe {
    typealias AudioBridgeFactory = @MainActor @Sendable (
        _ owner: MiniAppID,
        _ stopNativeOnly: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation.AcquireAudio
    /// Parent supplies the P2-1 bridge. Its stop callback stops only the native
    /// producer and never calls owner.stop()/the returned release recursively.
    static var makeAcquireAudio: AudioBridgeFactory?
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
final class MediaCaptureConsentGate {
    let owner: MiniAppID
    var store: MiniAppConsentStore?
    init(owner: MiniAppID, store: MiniAppConsentStore? = nil) {
        self.owner = owner
        self.store = store
    }
    func allows(_ resource: MiniAppCaptureResource) -> Bool {
        store?.consent(for: owner, permissionID: resource.rawValue) == .allowed
    }
}

@MainActor
final class MediaCaptureFixtureState: ObservableObject {
    @Published var status = "準備前"
    @Published var resultCount = 0
    @Published var retainedValue = 0
    @Published var generation = 0
    @Published var photoData: Data?
    @Published var documentPages: [Data] = []
    @Published var code: String?
    @Published var movieURL: URL?
}

@MainActor
final class PhotoFixture {
    let id = MiniAppID("media-photo")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    let consentGate: MediaCaptureConsentGate
    private var movieProducer: MiniAppAVCaptureSessionProducer?
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.owner.connect(to: runtime)
        self.state.generation += 1
        self.state.status = "写真: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator,
         permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
         consentStore: MiniAppConsentStore? = nil) {
        let featureID = MiniAppID("media-photo")
        let gate = MediaCaptureConsentGate(owner: featureID, store: consentStore)
        consentGate = gate
        owner = MiniAppCaptureOwner(id: featureID, coordinator: coordinator,
                                    permissions: permissions,
                                    consent: { [gate] in gate.allows($0) })
        let fixtureState = state
        owner.stateChanged = { [weak fixtureState] captureState in
            switch captureState {
            case .suspended, .failed, .stopped:
                fixtureState?.status = "撮影停止: \(captureState)"
            case .stopping where fixtureState?.status.contains("録画中") == true:
                fixtureState?.status = "撮影停止中: \(captureState)"
            default: break
            }
        }
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
        let operation = MiniAppCaptureOperation(
            resources: [.camera], nativeEvents: { await producer.events() },
            restartNative: { try await producer.restartAfterInterruption() },
            startNative: { [weak self] in
                try await producer.start()
                self?.state.status = "写真: camera実行中"
                return { _ in await producer.stop() }
            }
        )
        do {
            try await owner.start(operation, switching: .stopCurrent)
            let data = try await producer.capturePhoto()
            // Fixture/Feature owns the result bytes; Core never stores them.
            state.resultCount += data.isEmpty ? 0 : 1
            state.photoData = data
            state.retainedValue += 1
            state.status = "写真成功 \(state.resultCount)件"
            await owner.stop()
        } catch {
            state.status = "写真失敗: \(error)"
        }
    }

    func recordAudioMovie() async {
        let producer = MiniAppAVCaptureSessionProducer(mode: .movie, includesAudio: true)
        guard let acquireAudio = MediaCaptureProbe.makeAcquireAudio?(id, { await producer.stop() }) else {
            state.status = "音声付き動画: Audio接続未統合"
            return
        }
        movieProducer = producer
        if let old = state.movieURL { try? FileManager.default.removeItem(at: old) }
        state.movieURL = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-capture-\(UUID().uuidString).mov")
        let operation = MiniAppCaptureOperation(
            resources: [.camera, .microphone], acquireAudio: acquireAudio,
            nativeEvents: { await producer.events() },
            restartNative: { try await producer.restartAfterInterruption() },
            startNative: { [weak self] in
                do {
                    try await producer.start()
                    try await producer.startMovie(to: url)
                } catch {
                    await producer.stop()
                    try? FileManager.default.removeItem(at: url)
                    self?.movieProducer = nil
                    throw error
                }
                self?.state.status = "音声付き動画: 録画中"
                return { [weak self] _ in
                    await producer.stop()
                    await self?.finishMovie(producer)
                }
            }
        )
        do {
            try await owner.start(operation, switching: .stopCurrent)
            state.retainedValue = url.path.count
        } catch { state.status = "音声付き動画失敗: \(error)" }
    }

    func stop() async {
        await owner.stop()
        if movieProducer == nil, state.movieURL == nil { state.status = "撮影停止・camera解放" }
    }

    private func finishMovie(_ producer: MiniAppAVCaptureSessionProducer) async {
        guard movieProducer === producer else { return }
        if let completion = await producer.movieCompletion() { applyMovieCompletion(completion) }
        movieProducer = nil
    }

    func applyMovieCompletion(_ completion: MiniAppMovieCompletion) {
        switch completion {
        case .succeeded(let url):
            state.movieURL = url
            state.resultCount += 1
            state.status = "動画成功・camera解放"
        case .failed(let url, let reason):
            try? FileManager.default.removeItem(at: url)
            state.status = "動画失敗・camera解放: \(reason)"
        }
    }
}

@MainActor
final class ScannerFixture {
    let id = MiniAppID("media-scanner")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    let presentations: MiniAppPresentationOwner
    let consentGate: MediaCaptureConsentGate
    let presentationAnchor = MediaCapturePresentationAnchor()
    private var adapter: MiniAppVisionCaptureAdapter?
    typealias DocumentOperationFactory = @MainActor (
        @escaping @MainActor @Sendable (Result<[Data], Error>) -> Void,
        @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation
    private let documentOperationOverride: DocumentOperationFactory?
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        // Runtime cleanup is reverse registration order: capture native stop and
        // adapter dismissal run before the presentation owner's final sweep.
        try self.presentations.connect(to: runtime)
        try self.owner.connect(to: runtime)
        self.adapter = MiniAppVisionCaptureAdapter(
            presentationOwner: self.presentations,
            present: { [weak self] controller in
                guard let self else { throw MiniAppCaptureFailure.stopped }
                try await self.presentationAnchor.present(controller)
            },
            dismiss: { [weak self] controller in
                await self?.presentationAnchor.dismiss(controller)
            }
        )
        self.state.generation += 1
        self.state.status = "scan: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator,
         permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
         consentStore: MiniAppConsentStore? = nil,
         documentOperation: DocumentOperationFactory? = nil) {
        let featureID = MiniAppID("media-scanner")
        let gate = MediaCaptureConsentGate(owner: featureID, store: consentStore)
        consentGate = gate
        documentOperationOverride = documentOperation
        owner = MiniAppCaptureOwner(id: featureID, coordinator: coordinator,
                                    permissions: permissions,
                                    consent: { [gate] in gate.allows($0) })
        presentations = MiniAppPresentationOwner(id: featureID)
        let fixtureState = state
        owner.stateChanged = { [weak fixtureState] captureState in
            switch captureState {
            case .stopping, .suspended, .failed, .stopped:
                fixtureState?.status = "scan停止: \(captureState)"
            default: break
            }
        }
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
            let result: @MainActor @Sendable (Result<[Data], Error>) -> Void = { [weak self] result in
                switch result {
                case .success(let pages):
                    self?.state.resultCount += pages.count
                    self?.state.documentPages = pages
                    self?.state.retainedValue += pages.count
                    self?.state.status = "文書成功 \(pages.count)ページ"
                case .failure(let error): self?.state.status = "文書取消/失敗: \(error)"
                }
            }
            let ended: @MainActor @Sendable () async -> Void = { [weak self] in await self?.owner.stop() }
            let operation = documentOperationOverride?(result, ended)
                ?? adapter.documentOperation(result: result, ended: ended)
            try await owner.start(operation, switching: .stopCurrent)
        } catch { state.status = "文書開始失敗: \(error)" }
    }

    func scanCode() async {
        guard let adapter else { state.status = "code scan: 未接続"; return }
        do {
            try await owner.start(adapter.codeOperation(result: { [weak self] code in
                self?.state.resultCount += 1
                self?.state.retainedValue = code.count
                self?.state.code = code
                self?.state.status = "code成功: \(code)"
            }, failure: { [weak self] failure in
                self?.state.status = "code失敗: \(failure)"
            }, ended: { [weak self] in await self?.owner.stop() }), switching: .stopCurrent)
        } catch { state.status = "code開始失敗: \(error)" }
    }

    func stop() async {
        await owner.stop()
        state.status = "scan停止・camera解放"
    }
}

private struct PhotoProbeView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
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
            if let data = state.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("撮影した写真")
            }
            if let url = state.movieURL {
                MediaCaptureMoviePreview(url: url)
            }
        }
        .onAppear { fixture.consentGate.store = consentStore }
    }
}

private struct ScannerProbeView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
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
            if let data = state.documentPages.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("scanした文書の先頭ページ")
            }
            if let code = state.code { Text(code).textSelection(.enabled) }
        }
        .background(MediaCapturePresentationAnchorView(anchor: fixture.presentationAnchor))
        .onAppear { fixture.consentGate.store = consentStore }
    }
}

private struct MediaCaptureMoviePreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View {
        VideoPlayer(player: player).frame(minHeight: 180)
            .accessibilityLabel("撮影した動画")
            .onDisappear { player.pause() }
    }
}

@MainActor
final class MediaCapturePresentationAnchor {
    weak var controller: UIViewController?

    func present(_ presented: UIViewController) async throws {
        guard let source = controller, source.viewIfLoaded?.window != nil else {
            throw MiniAppCaptureFailure.unavailable("feature scene presenter")
        }
        var presenter = source
        while let next = presenter.presentedViewController { presenter = next }
        await withCheckedContinuation { continuation in
            presenter.present(presented, animated: true) { continuation.resume() }
        }
    }

    func dismiss(_ presented: UIViewController) async {
        guard let presenter = presented.presentingViewController,
              presenter.presentedViewController === presented else { return }
        await withCheckedContinuation { continuation in
            presenter.dismiss(animated: true) { continuation.resume() }
        }
    }
}

private struct MediaCapturePresentationAnchorView: UIViewControllerRepresentable {
    let anchor: MediaCapturePresentationAnchor
    func makeUIViewController(context: Context) -> AnchorController {
        AnchorController(anchor: anchor)
    }
    func updateUIViewController(_ controller: AnchorController, context: Context) {
        anchor.controller = controller
    }

    final class AnchorController: UIViewController {
        let anchor: MediaCapturePresentationAnchor
        init(anchor: MediaCapturePresentationAnchor) { self.anchor = anchor; super.init(nibName: nil, bundle: nil) }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            anchor.controller = self
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if anchor.controller === self { anchor.controller = nil }
        }
    }
}
