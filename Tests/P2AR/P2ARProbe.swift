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
    let contenderOwner: MiniAppCaptureOwner
    let session: ARSession
    let configuration: ARWorldTrackingConfiguration
    let eventBridge: MiniAppARSessionEventBridge
    let adapter: MiniAppARSessionAdapter
    let delegate: P2ARFeatureDelegate
    let lifetime: MiniAppFeatureLifetime
    private let consentGate: P2ARConsentGate
    private let contenderOperation: @MainActor () -> MiniAppCaptureOperation
    private var contenderScenes: [UUID: MiniAppSceneActivityDispatcher] = [:]

    init(
        id: MiniAppID = MiniAppID("p2-ar"),
        coordinator: MiniAppCaptureCoordinator = .shared,
        permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
        contenderOperation: (@MainActor () -> MiniAppCaptureOperation)? = nil
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
        let contender = MiniAppCaptureOwner(
            id: MiniAppID("p2-ar-camera-contender"), coordinator: coordinator,
            permissions: permissions, consent: { [gate] in gate.allows($0) }
        )
        contenderOwner = contender
        self.contenderOperation = contenderOperation ?? { Self.makeRealCameraOperation() }
        lifetime = MiniAppFeatureLifetime(id: id) { [captureOwner, contender, state] runtime in
            try captureOwner.connect(to: runtime)
            try contender.connect(to: runtime)
            state.runtimeGeneration += 1
            state.status = "AR利用可能"
            state.append("runtime connected generation=\(state.runtimeGeneration)")
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
            state?.observeARState(captureState)
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
        contender.stateChanged = { [weak state] captureState in
            state?.contenderStatus = "Camera B: \(captureState)"
            state?.append("Camera B owner state=\(captureState)")
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
            onConsentChange: { [weak captureOwner = owner, weak contenderOwner = contenderOwner] permissionID, decision in
                guard permissionID == "camera", decision != .allowed else { return }
                Task { @MainActor in
                    await captureOwner?.suspend(.featureStopped)
                    await contenderOwner?.suspend(.featureStopped)
                }
            },
            onSceneActivityChange: { [weak self] in self?.receiveSceneActivity($0) }
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

    func startContender(switching: MiniAppCaptureSwitch, in sceneID: UUID?) async {
        guard let sceneID else { state.contenderStatus = "Camera B: scene未接続"; return }
        guard let contenderSceneID = contenderScenes[sceneID]?.connectionID else {
            state.contenderStatus = "Camera B: 対応scene未接続"
            return
        }
        do {
            try await contenderOwner.start(
                contenderOperation(), switching: switching, sceneScope: .scene(contenderSceneID)
            )
            state.contenderStatus = "Camera B: 実行中"
        } catch {
            state.contenderStatus = "Camera B: 拒否/失敗 \(error)"
            state.append("Camera B request result=\(error)")
        }
    }

    func stopContender() async {
        await contenderOwner.stop()
        state.contenderStatus = "Camera B: 停止・camera解放"
    }

    private func receiveSceneActivity(_ activity: MiniAppSceneActivity) {
        owner.receive(activity)
        if let phase = activity.phase {
            let dispatcher: MiniAppSceneActivityDispatcher
            if let existing = contenderScenes[activity.sceneID] {
                dispatcher = existing
            } else {
                dispatcher = MiniAppSceneActivityDispatcher(handlers: [
                    .init(id: contenderOwner.id) { [weak contenderOwner = contenderOwner] in
                        contenderOwner?.receive($0)
                    }
                ])
                contenderScenes[activity.sceneID] = dispatcher
            }
            dispatcher.connect(
                phase: phase,
                selectedID: activity.isSelected ? contenderOwner.id : nil
            )
        } else if let dispatcher = contenderScenes.removeValue(forKey: activity.sceneID) {
            dispatcher.disconnect()
        }
    }

    private static func makeRealCameraOperation() -> MiniAppCaptureOperation {
        let producer = MiniAppAVCaptureSessionProducer(mode: .photo)
        return MiniAppCaptureOperation(
            resources: [.camera],
            nativeEvents: { try await producer.events() },
            restartNative: { try await producer.restartAfterInterruption() },
            startNative: {
                try await producer.start()
                return { _ in await producer.stop() }
            }
        )
    }
}

@MainActor
final class P2ARState: ObservableObject {
    @Published var status = "未接続"
    @Published var frameCount = 0
    @Published var anchorCount = 0
    @Published var runtimeGeneration = 0
    @Published var contenderStatus = "Camera B: 停止中"
    @Published private(set) var observationLines: [String] = []
    private var waitingForFrameAfterInterruption = false

    func append(_ message: String) {
        observationLines.append("\(Date.now.ISO8601Format()) \(message)")
        if observationLines.count > 80 { observationLines.removeFirst(observationLines.count - 80) }
    }

    func osInterruptionBegan() {
        append("OS ARSessionDelegate interruption began")
    }

    func osInterruptionEnded() {
        waitingForFrameAfterInterruption = true
        append("OS ARSessionDelegate interruption ended; restart pending")
    }

    func observeARState(_ value: MiniAppCaptureState) {
        append("AR owner state=\(value)")
        if waitingForFrameAfterInterruption, case .running = value {
            append("AR restart completed after OS interruption")
        } else if waitingForFrameAfterInterruption {
            switch value {
            case .failed(_), .stopped, .suspended(.failure(_)), .suspended(.user),
                 .suspended(.featureStopped), .suspended(.switched(to: _)):
                waitingForFrameAfterInterruption = false
                append("AR interruption recovery ended without a resumed frame")
            default: break
            }
        }
    }

    func receivedFrame() {
        frameCount += 1
        if waitingForFrameAfterInterruption {
            waitingForFrameAfterInterruption = false
            append("first frame after OS interruption")
        }
    }
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
        Task { @MainActor [weak state] in state?.receivedFrame() }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let count = anchors.count
        Task { @MainActor [weak state] in state?.anchorCount += count }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak state] in state?.osInterruptionBegan() }
        currentForwarder()?.interruptionBegan()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak state] in state?.osInterruptionEnded() }
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
            Section("同一画面のcamera競合") {
                Text(state.contenderStatus).accessibilityIdentifier("p2.ar.contender.status")
                Button("Camera B要求（reject）") {
                    Task { await feature.startContender(switching: .reject, in: sceneID) }
                }
                Button("Camera B要求（stopCurrent）") {
                    Task { await feature.startContender(switching: .stopCurrent, in: sceneID) }
                }
                Button("Camera B停止") { Task { await feature.stopContender() } }
            }
            Section("AR観測（最大80行）") {
                ShareLink("AR観測を共有", item: state.observationLines.joined(separator: "\n"))
                Text(state.observationLines.isEmpty ? "記録なし" : state.observationLines.joined(separator: "\n"))
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .onAppear { feature.attachConsent(consentStore) }
    }
}
#endif
