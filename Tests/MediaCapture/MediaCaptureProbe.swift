import AVFoundation
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
final class MediaCaptureFixtureState: ObservableObject {
    @Published var status = "準備前"
    @Published var resultCount = 0
    @Published var retainedValue = 0
    @Published var generation = 0
    @Published var photoData: Data?
    @Published var documentPages: [Data] = []
    @Published var code: String?
    @Published var movieURL: URL?
    @Published var movieOutcome: String?
}

@MainActor
final class PhotoFixture {
    typealias PhotoCaptureOverride = @MainActor (MiniAppCaptureOwner) async throws -> Data
    let id = MiniAppID("media-photo")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    let consent: MiniAppConsentSource
    private var movieProducer: MiniAppAVCaptureSessionProducer?
    var hasActiveMovieProducer: Bool { movieProducer != nil }
    private let photoCaptureOverride: PhotoCaptureOverride?
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.owner.connect(to: runtime)
        self.state.generation += 1
        self.state.status = "写真: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator,
         permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
         consentStore: MiniAppConsentStore? = nil,
         photoCapture: PhotoCaptureOverride? = nil) {
        let featureID = MiniAppID("media-photo")
        let consent = MiniAppConsentSource(featureID: featureID, store: consentStore)
        self.consent = consent
        photoCaptureOverride = photoCapture
        owner = MiniAppCaptureOwner(id: featureID, coordinator: coordinator,
                                    permissions: permissions, consent: consent)
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
        ) { [self] _ in
            PhotoProbeView(fixture: self)
        }
    }

    func takePhoto() async {
        do {
            let data: Data
            if let photoCaptureOverride {
                data = try await photoCaptureOverride(owner)
            } else {
                let producer = MiniAppAVCaptureSessionProducer(mode: .photo)
                let operation = MiniAppCaptureOperation(
                    resources: [.camera], nativeEvents: { try await producer.events() },
                    restartNative: { try await producer.restartAfterInterruption() },
                    startNative: { [weak self] in
                        try await producer.start()
                        self?.state.status = "写真: camera実行中"
                        return { _ in await producer.stop() }
                    }
                )
                try await owner.start(operation, switching: .stopCurrent)
                data = try await producer.capturePhoto()
            }
            // Fixture/Feature owns the result bytes; Core never stores them.
            state.resultCount += data.isEmpty ? 0 : 1
            state.photoData = data
            state.retainedValue += 1
            state.status = "写真成功 \(state.resultCount)件"
            await owner.stop()
        } catch {
            state.status = "写真失敗: \(error)"
            await owner.stop()
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
        state.movieOutcome = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-capture-\(UUID().uuidString).mov")
        let operation = MiniAppCaptureOperation(
            resources: [.camera, .microphone], acquireAudio: acquireAudio,
            nativeEvents: { try await producer.events() },
            stopsOnInterruption: true,
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
        } catch {
            await owner.stop()
            await producer.stop()
            try? FileManager.default.removeItem(at: url)
            if movieProducer === producer { movieProducer = nil }
            if state.movieURL == url {
                state.movieURL = nil
                state.resultCount = max(0, state.resultCount - 1)
            }
            state.status = "音声付き動画失敗: \(error)"
            state.movieOutcome = "動画失敗: \(error)"
        }
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
            state.movieOutcome = "部分成果を含む動画を保存しました"
        case .failed(let url, let reason):
            try? FileManager.default.removeItem(at: url)
            state.status = "動画失敗・camera解放: \(reason)"
            state.movieOutcome = "動画失敗: \(reason)"
        }
    }
}

@MainActor
final class ScannerFixture {
    let id = MiniAppID("media-scanner")
    let state = MediaCaptureFixtureState()
    let owner: MiniAppCaptureOwner
    let presentations: MiniAppPresentationOwner
    let consent: MiniAppConsentSource
    let presentationAnchor = MiniAppPresentationAnchor()
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
        self.adapter = MiniAppVisionCaptureAdapter(presentationOwner: self.presentations,
                                                   anchor: self.presentationAnchor)
        self.state.generation += 1
        self.state.status = "scan: 利用可能"
    }

    init(coordinator: MiniAppCaptureCoordinator,
         permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
         consentStore: MiniAppConsentStore? = nil,
         documentOperation: DocumentOperationFactory? = nil) {
        let featureID = MiniAppID("media-scanner")
        let consent = MiniAppConsentSource(featureID: featureID, store: consentStore)
        self.consent = consent
        documentOperationOverride = documentOperation
        owner = MiniAppCaptureOwner(id: featureID, coordinator: coordinator,
                                    permissions: permissions, consent: consent)
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
        ) { [self] _ in
            ScannerProbeView(fixture: self)
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
                ShareLink(item: url) {
                    Label("保存した動画を共有して確認", systemImage: "square.and.arrow.up")
                }
            }
            if let outcome = state.movieOutcome { Text(outcome) }
        }
        .miniAppConsentSource(fixture.consent)
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
            if let data = state.documentPages.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("scanした文書の先頭ページ")
            }
            if let code = state.code { Text(code).textSelection(.enabled) }
        }
        .miniAppPresentationAnchor(fixture.presentationAnchor)
        .miniAppConsentSource(fixture.consent)
    }
}
