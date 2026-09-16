import Foundation

@MainActor
public final class MiniAppCaptureOwner {
    public nonisolated let id: MiniAppID
    public private(set) var state: MiniAppCaptureState = .idle

    private let coordinator: MiniAppCaptureCoordinator
    private let permissions: any MiniAppCapturePermissionClient
    private weak var runtime: MiniAppRuntime?
    private var runtimeGeneration: UUID?
    private var operationGeneration: UUID?
    private var scenes: [UUID: MiniAppSceneActivity] = [:]
    private var stopNative: MiniAppCaptureOperation.Stop?
    private var releaseAudio: (@MainActor @Sendable () async -> Void)?
    private var stopTask: Task<Void, Never>?
    private var explicitEnd = false

    public init(
        id: MiniAppID,
        coordinator: MiniAppCaptureCoordinator = .shared,
        permissions: any MiniAppCapturePermissionClient
    ) {
        precondition(id.isValid)
        self.id = id
        self.coordinator = coordinator
        self.permissions = permissions
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        guard runtimeGeneration == nil else { throw MiniAppCaptureFailure.native("already connected") }
        guard !runtime.isClosed else { throw MiniAppCaptureFailure.stopped }
        let generation = UUID()
        self.runtime = runtime
        runtimeGeneration = generation
        state = .idle
        explicitEnd = false
        try runtime.onShutdownAsync { [weak self] in
            await self?.stop(reason: .featureStopped, final: true, runtimeGeneration: generation)
        }
    }

    /// Feed every scene callback to this owner. Capture remains eligible while
    /// at least one connected scene is active and selected.
    public func receive(_ activity: MiniAppSceneActivity) {
        guard activity.featureID == id else { return }
        if activity.isConnected { scenes[activity.sceneID] = activity }
        else { scenes[activity.sceneID] = nil }
        guard isVisible else {
            let reason: MiniAppCaptureStopReason
            if activity.phase == nil { reason = .disconnected }
            else if activity.phase == .background { reason = .background }
            else if !activity.isSelected { reason = .notSelected }
            else { reason = .sceneInactive }
            Task { @MainActor [weak self] in
                guard let self, !self.isVisible else { return }
                await self.suspend(reason)
            }
            return
        }
    }

    public func start(
        _ operation: MiniAppCaptureOperation,
        switching: MiniAppCaptureSwitch = .reject
    ) async throws {
        while let stopTask { await stopTask.value }
        guard let runtimeGeneration, runtime?.isClosed == false else { throw MiniAppCaptureFailure.stopped }
        guard operationGeneration == nil else { throw MiniAppCaptureFailure.unavailable("capture already active") }
        guard isVisible else { throw MiniAppCaptureFailure.unavailable("no active selected scene") }
        explicitEnd = false
        let generation = UUID()
        operationGeneration = generation
        state = .requesting(operation.resources)

        do {
            for resource in [MiniAppCaptureResource.camera, .microphone] where operation.resources.contains(resource) {
                guard await permissions.request(resource) else {
                    throw MiniAppCaptureFailure.osPermissionDenied(resource)
                }
                try check(generation: generation, runtimeGeneration: runtimeGeneration)
            }
            if operation.resources.contains(.microphone), operation.acquireAudio == nil {
                throw MiniAppCaptureFailure.missingAudioHook
            }
            try await coordinator.reserveCamera(
                owner: id, generation: generation, switching: switching,
                stopProducer: { [weak self] reason in await self?.stop(reason: reason, final: false) }
            )
            try check(generation: generation, runtimeGeneration: runtimeGeneration)

            if let acquireAudio = operation.acquireAudio {
                guard operation.resources.contains(.microphone) else {
                    throw MiniAppCaptureFailure.native("audio hook supplied to camera-only operation")
                }
                let acquiredAudio = try await acquireAudio()
                do { try check(generation: generation, runtimeGeneration: runtimeGeneration) }
                catch {
                    await acquiredAudio()
                    throw error
                }
                releaseAudio = acquiredAudio
            }
            state = .starting
            let startedNative = try await operation.startNative()
            do { try check(generation: generation, runtimeGeneration: runtimeGeneration) }
            catch {
                await startedNative(.failure("start completed after cancellation"))
                throw error
            }
            stopNative = startedNative
            state = .running(operation.resources)
        } catch {
            let failure = error as? MiniAppCaptureFailure ?? .native(String(describing: error))
            if operationGeneration == generation {
                operationGeneration = nil
                await releasePartial(generation: generation, reason: .failure(String(describing: error)))
                if self.runtimeGeneration == runtimeGeneration { state = .failed(failure) }
            } else {
                // A stop/new generation already released this operation. The
                // generation check prevents this late callback touching it.
                coordinator.releaseCamera(owner: id, generation: generation)
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

    public func handleInterruptionEnded(
        restart: @MainActor @Sendable () async throws -> Void
    ) async throws {
        guard !explicitEnd, isVisible, case .suspended(.interrupted(_)) = state else { return }
        try await restart()
    }

    private var isVisible: Bool {
        scenes.values.contains { $0.phase == .active && $0.isSelected }
    }

    private func check(generation: UUID, runtimeGeneration: UUID) throws {
        guard self.runtimeGeneration == runtimeGeneration else { throw MiniAppCaptureFailure.staleGeneration }
        guard operationGeneration == generation, runtime?.isClosed == false else { throw MiniAppCaptureFailure.stopped }
        guard !Task.isCancelled else { throw CancellationError() }
    }

    private func stop(
        reason: MiniAppCaptureStopReason,
        final: Bool,
        runtimeGeneration expectedRuntimeGeneration: UUID? = nil
    ) async {
        if let expectedRuntimeGeneration, runtimeGeneration != expectedRuntimeGeneration { return }
        if let stopTask { await stopTask.value; return }
        guard let generation = operationGeneration else {
            if final {
                runtime = nil
                runtimeGeneration = nil
                scenes.removeAll()
                state = .stopped
            }
            return
        }
        operationGeneration = nil // close admission before awaiting native work
        state = .stopping(reason)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.releasePartial(generation: generation, reason: reason)
            if final {
                self.runtime = nil
                self.runtimeGeneration = nil
                self.scenes.removeAll()
                self.state = .stopped
            } else {
                self.state = reason == .user ? .idle : .suspended(reason)
            }
            self.stopTask = nil
        }
        stopTask = task
        await task.value
    }

    /// Required order: producer stop, then its presentation-aware native stop
    /// closure returns, then audio lease, then camera reservation.
    private func releasePartial(generation: UUID, reason: MiniAppCaptureStopReason) async {
        if let stopNative {
            self.stopNative = nil
            await stopNative(reason)
        }
        if let releaseAudio {
            self.releaseAudio = nil
            await releaseAudio()
        }
        coordinator.releaseCamera(owner: id, generation: generation)
    }
}
