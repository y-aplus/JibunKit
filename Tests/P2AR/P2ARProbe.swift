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
    private let consentGate: P2ARConsentGate

    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.owner.connect(to: runtime)
        self.state.runtimeGeneration += 1
        self.state.status = "AR利用可能"
    }

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
        owner = MiniAppCaptureOwner(
            id: id, coordinator: coordinator, permissions: permissions,
            consent: { [gate] in gate.allows($0) }
        )
        let arSession = ARSession()
        let arConfiguration = ARWorldTrackingConfiguration()
        let bridge = MiniAppARSessionEventBridge()
        let featureDelegate = P2ARFeatureDelegate(state: state, events: bridge)
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
            isSupported: { ARWorldTrackingConfiguration.isSupported }
        )
        arSession.delegate = featureDelegate
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: "AR Probe", systemImage: "arkit",
            lifetime: lifetime,
            permissions: [
                .init(id: "camera", title: "カメラ", purpose: "前景AR表示に使います",
                      deniedBehavior: "ARSessionを開始しません")
            ],
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
    private let events: MiniAppARSessionEventBridge

    init(state: P2ARState, events: MiniAppARSessionEventBridge) {
        self.state = state
        self.events = events
        super.init()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak state] in state?.frameCount += 1 }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let count = anchors.count
        Task { @MainActor [weak state] in state?.anchorCount += count }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        events.interruptionBegan()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        events.interruptionEnded()
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        events.runtimeFailed(reason: String(describing: error), canRestart: false)
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
