#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import JibunKitCore
import SwiftUI

@MainActor
enum P2ARProbe {
    static let feature = P2ARFeature()
    static var definitions: [MiniAppDefinition] { [feature.definition] }
}

@MainActor
final class P2ARFeature {
    let id: MiniAppID
    let state: P2ARState
    let owner: MiniAppCaptureOwner
    let session: ARSession
    let configuration: ARWorldTrackingConfiguration
    let eventBridge: MiniAppARSessionEventBridge
    let adapter: MiniAppARSessionAdapter
    let delegate: P2ARFeatureDelegate
    let lifetime: MiniAppFeatureLifetime
    private let consentGate: P2ARConsentGate

    init(
        id: MiniAppID = MiniAppID("p2-ar"),
        coordinator: MiniAppCaptureCoordinator = .shared,
        permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient()
    ) {
        self.id = id
        let state = P2ARState()
        self.state = state
        let gate = P2ARConsentGate(owner: id)
        consentGate = gate
        let captureOwner = MiniAppCaptureOwner(
            id: id, coordinator: coordinator, permissions: permissions,
            consent: { [gate] in gate.allows($0) }
        )
        owner = captureOwner
        lifetime = MiniAppFeatureLifetime(id: id) { [captureOwner, state] runtime in
            try captureOwner.connect(to: runtime)
            state.runtimeGeneration += 1
            state.status = "AR利用可能"
        }
        let arSession = ARSession()
        let arConfiguration = ARWorldTrackingConfiguration()
        let bridge = MiniAppARSessionEventBridge()
        let featureDelegate = P2ARFeatureDelegate(state: state)
        session = arSession
        configuration = arConfiguration
        eventBridge = bridge
        delegate = featureDelegate
        adapter = MiniAppARSessionAdapter(
            session: arSession,
            configuration: arConfiguration,
            runOptions: [.resetTracking, .removeExistingAnchors],
            restartOptions: [],
            eventBridge: bridge,
            isSupported: { ARWorldTrackingConfiguration.isSupported },
            installForwarder: { [weak featureDelegate] in featureDelegate?.install($0) },
            removeForwarder: { [weak featureDelegate] in featureDelegate?.remove(generation: $0) }
        )
        arSession.delegate = featureDelegate
        captureOwner.stateChanged = { [weak state] captureState in
            switch captureState {
            case .requesting: state?.status = "AR許可確認中"
            case .starting: state?.status = "AR開始中"
            case .running: state?.status = "AR実行中"
            case .stopping(let reason): state?.status = "AR停止中: \(reason)"
            case .suspended(let reason): state?.status = "AR中断/停止: \(reason)"
            case .failed(let failure): state?.status = "AR失敗: \(failure)"
            case .stopped: state?.status = "AR Feature停止"
            case .idle: state?.status = "AR利用可能"
            }
        }
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: "AR Probe", systemImage: "arkit",
            lifetime: lifetime,
            permissions: [
                .init(id: "camera", title: "カメラ", purpose: "前景AR表示に使います",
                      deniedBehavior: "ARSessionを開始しません")
            ],
            onConsentChange: { [weak captureOwner = owner] permissionID, decision in
                guard permissionID == "camera", decision != .allowed else { return }
                Task { @MainActor in await captureOwner?.suspend(.featureStopped) }
            },
            onSceneActivityChange: { [weak self] in self?.owner.receive($0) }
        ) { [self] _ in P2ARView(feature: self) }
    }

    func attachConsent(_ store: MiniAppConsentStore?) {
        consentGate.store = store
    }

    func start(in sceneID: UUID?) async {
        guard let sceneID else { state.status = "scene未接続"; return }
        do {
            try await owner.start(try adapter.operation(), sceneScope: .scene(sceneID))
            state.status = "AR実行中"
        } catch {
            state.status = "AR開始失敗: \(error)"
        }
    }

    func stop() async {
        await owner.stop()
        state.status = "AR停止・camera解放"
    }
}

@MainActor
final class P2ARState: ObservableObject {
    @Published var status = "未接続"
    @Published var frameCount = 0
    @Published var anchorCount = 0
    @Published var runtimeGeneration = 0
}

@MainActor
private final class P2ARConsentGate {
    let owner: MiniAppID
    var store: MiniAppConsentStore?
    init(owner: MiniAppID) { self.owner = owner }
    func allows(_ resource: MiniAppCaptureResource) -> Bool {
        resource == .camera && store?.consent(for: owner, permissionID: "camera") == .allowed
    }
}

/// The Feature remains the ARSession delegate. It receives standard frame and
/// anchor callbacks, forwarding only lifetime events to the Core bridge.
final class P2ARFeatureDelegate: NSObject, ARSessionDelegate, @unchecked Sendable {
    private weak var state: P2ARState?
    private let lock = NSLock()
    private var forwarder: MiniAppARSessionEventForwarder?

    init(state: P2ARState) {
        self.state = state
        super.init()
    }

    nonisolated func install(_ value: MiniAppARSessionEventForwarder) {
        lock.withLock { forwarder = value }
    }

    nonisolated func remove(generation: UUID) {
        lock.withLock {
            if forwarder?.generation == generation { forwarder = nil }
        }
    }

    private nonisolated func currentForwarder() -> MiniAppARSessionEventForwarder? {
        lock.withLock { forwarder }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak state] in state?.frameCount += 1 }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let count = anchors.count
        Task { @MainActor [weak state] in state?.anchorCount += count }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        currentForwarder()?.interruptionBegan()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        currentForwarder()?.interruptionEnded()
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        currentForwarder()?.runtimeFailed(reason: String(describing: error), canRestart: false)
    }
}

private struct P2ARView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
    @Environment(\.miniAppSceneActivityID) private var sceneID
    @ObservedObject var state: P2ARState
    let feature: P2ARFeature

    init(feature: P2ARFeature) {
        self.feature = feature
        state = feature.state
    }

    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("p2.ar.status")
            Text("frames \(state.frameCount) / anchors \(state.anchorCount) / runtime \(state.runtimeGeneration)")
                .accessibilityIdentifier("p2.ar.counts")
            Button("AR開始") { Task { await feature.start(in: sceneID) } }
                .accessibilityIdentifier("p2.ar.start")
            Button("AR停止") { Task { await feature.stop() } }
                .accessibilityIdentifier("p2.ar.stop")
        }
        .onAppear { feature.attachConsent(consentStore) }
    }
}
#endif
