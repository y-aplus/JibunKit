#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import Foundation

/// Converts only AR session lifetime events into the existing capture contract.
/// It never assigns `ARSession.delegate`: a Feature keeps its full frame/anchor
/// delegate and forwards the three observer callbacks it wants coordinated.
@MainActor
public final class MiniAppARSessionEventBridge: NSObject, @preconcurrency ARSessionDelegate {
    public nonisolated let canRestartRuntimeFailure: @Sendable (String) -> Bool
    private var active: MiniAppCaptureNativeEvents?
    private var continuation: AsyncStream<MiniAppCaptureNativeEvent>.Continuation?

    public init(canRestartRuntimeFailure: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.canRestartRuntimeFailure = canRestartRuntimeFailure
        super.init()
    }

    func begin() throws -> MiniAppCaptureNativeEvents {
        guard active == nil else { throw MiniAppCaptureFailure.unavailable("AR event bridge already active") }
        let generation = UUID()
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let events = MiniAppCaptureNativeEvents(generation: generation, stream: pair.stream)
        active = events
        continuation = pair.continuation
        return events
    }

    func events() throws -> MiniAppCaptureNativeEvents {
        guard let active else { throw MiniAppCaptureFailure.stopped }
        return active
    }

    func end() {
        continuation?.finish()
        continuation = nil
        active = nil
    }

    /// Call from a Feature-owned ARSessionDelegate when it keeps the delegate.
    public nonisolated func interruptionBegan(reason: String? = nil) {
        Task { @MainActor [weak self] in self?.emitInterruption(reason) }
    }

    /// Call from a Feature-owned ARSessionDelegate when it keeps the delegate.
    public nonisolated func interruptionEnded() {
        Task { @MainActor [weak self] in self?.emitInterruptionEnded() }
    }

    /// Call from a Feature-owned delegate to preserve its Error-specific policy.
    public nonisolated func runtimeFailed(reason: String, canRestart: Bool) {
        Task { @MainActor [weak self] in self?.emitRuntimeFailure(reason, canRestart: canRestart) }
    }

    public nonisolated func sessionWasInterrupted(_ session: ARSession) {
        interruptionBegan()
    }

    public nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        interruptionEnded()
    }

    public nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        let reason = String(describing: error)
        runtimeFailed(reason: reason, canRestart: canRestartRuntimeFailure(reason))
    }

    private func emitInterruption(_ reason: String?) {
        guard let generation = active?.generation else { return }
        continuation?.yield(.interrupted(generation: generation, reason: reason))
    }

    private func emitInterruptionEnded() {
        guard let generation = active?.generation else { return }
        continuation?.yield(.interruptionEnded(generation: generation))
    }

    private func emitRuntimeFailure(_ reason: String, canRestart: Bool) {
        guard let generation = active?.generation else { return }
        continuation?.yield(.runtimeFailed(
            generation: generation, reason: reason, canRestart: canRestart
        ))
    }
}

/// Adapts one Feature-owned ARSession to camera ownership without wrapping or
/// replacing ARConfiguration, frames, anchors, or the Feature's delegate.
@MainActor
public final class MiniAppARSessionAdapter {
    public let session: ARSession
    public let configuration: ARConfiguration
    public let eventBridge: MiniAppARSessionEventBridge
    private let runOptions: ARSession.RunOptions
    private let restartOptions: ARSession.RunOptions
    private let isSupported: @MainActor @Sendable () -> Bool

    public init(
        session: ARSession,
        configuration: ARConfiguration,
        runOptions: ARSession.RunOptions = [],
        restartOptions: ARSession.RunOptions = [],
        eventBridge: MiniAppARSessionEventBridge,
        isSupported: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.session = session
        self.configuration = configuration
        self.runOptions = runOptions
        self.restartOptions = restartOptions
        self.eventBridge = eventBridge
        self.isSupported = isSupported
    }

    public func operation() throws -> MiniAppCaptureOperation {
        guard isSupported() else { throw MiniAppCaptureFailure.unsupported }
        return MiniAppCaptureOperation(
            resources: [.camera],
            nativeEvents: { [eventBridge] in try eventBridge.events() },
            restartNative: { [weak self] in
                guard let self else { throw MiniAppCaptureFailure.stopped }
                guard self.isSupported() else { throw MiniAppCaptureFailure.unsupported }
                self.session.run(self.configuration, options: self.restartOptions)
            },
            startNative: { [weak self] in
                guard let self else { throw MiniAppCaptureFailure.stopped }
                guard self.isSupported() else { throw MiniAppCaptureFailure.unsupported }
                _ = try self.eventBridge.begin()
                self.session.run(self.configuration, options: self.runOptions)
                return { [weak self] _ in
                    guard let self else { return }
                    self.session.pause()
                    self.eventBridge.end()
                }
            }
        )
    }
}
#endif
