import Foundation

@MainActor
public final class MiniAppCaptureOwner {
    public nonisolated let id: MiniAppID
    public private(set) var state: MiniAppCaptureState = .idle {
        didSet { stateChanged?(state) }
    }
    public var stateChanged: (@MainActor @Sendable (MiniAppCaptureState) -> Void)?
    private struct Started: Sendable {
        let stop: MiniAppCaptureOperation.Stop
        let releaseAudio: (@MainActor @Sendable () async -> Void)?
    }
    @MainActor private final class Operation {
        let generation = UUID()
        var closed = false
        var startup: Task<Started, Error>?
    }
    private let coordinator: MiniAppCaptureCoordinator
    private let permissions: any MiniAppCapturePermissionClient
    private let consent: @MainActor @Sendable (MiniAppCaptureResource) -> Bool
    private weak var runtime: MiniAppRuntime?
    private var runtimeGeneration: UUID?
    private var operation: Operation?
    private var scenes: [UUID: MiniAppSceneActivity] = [:]
    private var stopTask: Task<Void, Never>?
    private var endingRuntime = false
    private var explicitEnd = false

    public init(id: MiniAppID, coordinator: MiniAppCaptureCoordinator = .shared,
                permissions: any MiniAppCapturePermissionClient,
                consent: @escaping @MainActor @Sendable (MiniAppCaptureResource) -> Bool = { _ in true }) {
        precondition(id.isValid)
        self.id = id
        self.coordinator = coordinator
        self.permissions = permissions
        self.consent = consent
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        guard runtimeGeneration == nil else { throw MiniAppCaptureFailure.native("already connected") }
        guard !runtime.isClosed else { throw MiniAppCaptureFailure.stopped }
        let generation = UUID()
        self.runtime = runtime
        runtimeGeneration = generation
        endingRuntime = false
        explicitEnd = false
        state = .idle
        try runtime.onShutdownAsync { [weak self] in
            guard let self, self.runtimeGeneration == generation else { return }
            await self.stop(reason: .featureStopped, final: true)
        }
    }

    public func receive(_ activity: MiniAppSceneActivity) {
        guard activity.featureID == id else { return }
        if activity.isConnected { scenes[activity.sceneID] = activity }
        else { scenes[activity.sceneID] = nil }
        guard !isVisible else { return }
        let reason: MiniAppCaptureStopReason
        if activity.phase == nil { reason = .disconnected }
        else if activity.phase == .background { reason = .background }
        else if !activity.isSelected { reason = .notSelected }
        else { reason = .sceneInactive }
        Task { @MainActor [weak self] in
            guard let self, !self.isVisible else { return }
            await self.suspend(reason)
        }
    }

    public func start(_ request: MiniAppCaptureOperation,
                      switching: MiniAppCaptureSwitch = .reject) async throws {
        while let stopTask { await stopTask.value }
        guard let runtimeGeneration, runtime?.isClosed == false else { throw MiniAppCaptureFailure.stopped }
        guard operation == nil else { throw MiniAppCaptureFailure.unavailable("capture already active") }
        guard isVisible else { throw MiniAppCaptureFailure.unavailable("no active selected scene") }
        let pending = Operation()
        operation = pending
        explicitEnd = false
        state = .requesting(request.resources)
        do {
            for resource in [MiniAppCaptureResource.camera, .microphone] where request.resources.contains(resource) {
                guard consent(resource) else { throw MiniAppCaptureFailure.featureConsentDenied(resource) }
                let allowed = await permissions.request(resource)
                try check(pending, runtimeGeneration)
                guard allowed else { throw MiniAppCaptureFailure.osPermissionDenied(resource) }
            }
            guard request.resources.contains(.microphone) == (request.acquireAudio != nil) else {
                throw MiniAppCaptureFailure.missingAudioHook
            }
            try await coordinator.reserveCamera(owner: id, generation: pending.generation,
                switching: switching, accepting: { [weak self] in
                    !pending.closed && self?.runtime?.isClosed == false
                }, stopProducer: { [weak self] reason in
                    await self?.stop(reason: reason, final: false)
                })
            try check(pending, runtimeGeneration)
            state = .starting
            // Stop joins this phase before handing camera/audio to another owner.
            let startup = Task { @MainActor in
                let audio = try await request.acquireAudio?()
                do {
                    guard !pending.closed else { throw MiniAppCaptureFailure.stopped }
                    let stop = try await request.startNative()
                    return Started(stop: stop, releaseAudio: audio)
                } catch {
                    await audio?()
                    throw error
                }
            }
            pending.startup = startup
            _ = try await startup.value
            try check(pending, runtimeGeneration)
            state = .running(request.resources)
        } catch {
            let failure = error as? MiniAppCaptureFailure ?? .native(String(describing: error))
            if operation === pending {
                await stop(reason: .failure(String(describing: error)), final: false)
                if self.runtimeGeneration == runtimeGeneration,
                   case .suspended(.failure(_)) = state { state = .failed(failure) }
            } else {
                coordinator.releaseCamera(owner: id, generation: pending.generation)
            }
            throw failure
        }
    }

    public func stop() async {
        explicitEnd = true
        await stop(reason: .user, final: false)
    }

    public func suspend(_ reason: MiniAppCaptureStopReason) async {
        await stop(reason: reason, final: false)
    }

    public func handleInterruptionEnded(restart: @MainActor @Sendable () async throws -> Void) async throws {
        guard !explicitEnd, isVisible, runtime?.isClosed == false,
              case .suspended(.interrupted(_)) = state else { return }
        try await restart()
    }

    private var isVisible: Bool { scenes.values.contains { $0.phase == .active && $0.isSelected } }

    private func check(_ pending: Operation, _ generation: UUID) throws {
        guard runtimeGeneration == generation else { throw MiniAppCaptureFailure.staleGeneration }
        guard operation === pending, !pending.closed, runtime?.isClosed == false else {
            throw MiniAppCaptureFailure.stopped
        }
        guard isVisible else { throw MiniAppCaptureFailure.unavailable("no active selected scene") }
        try Task.checkCancellation()
    }

    private func stop(reason: MiniAppCaptureStopReason, final: Bool) async {
        if final { endingRuntime = true }
        if let stopTask { await stopTask.value; finishRuntimeIfNeeded(); return }
        guard let pending = operation else { finishRuntimeIfNeeded(); return }
        pending.closed = true
        state = .stopping(reason)
        let task = Task { @MainActor in
            if let startup = pending.startup, case .success(let started) = await startup.result {
                await started.stop(reason)
                await started.releaseAudio?()
            }
            self.coordinator.releaseCamera(owner: self.id, generation: pending.generation)
            if self.operation === pending { self.operation = nil }
            self.state = reason == .user ? .idle : .suspended(reason)
            self.stopTask = nil
            self.finishRuntimeIfNeeded()
        }
        stopTask = task
        await task.value
    }

    private func finishRuntimeIfNeeded() {
        guard endingRuntime else { return }
        runtime = nil
        runtimeGeneration = nil
        // Preserve scene observations across restart in an unchanged host scene.
        state = .stopped
        endingRuntime = false
    }
}
