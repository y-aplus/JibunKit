import Foundation

public enum MiniAppCaptureResource: String, Sendable, Hashable, Codable {
    case camera
    case microphone
}

public enum MiniAppCaptureSwitch: Sendable, Equatable {
    case reject
    case stopCurrent
}

public enum MiniAppCaptureStopReason: Sendable, Equatable {
    case user
    case sceneInactive
    case background
    case notSelected
    case disconnected
    case featureStopped
    case switched(to: MiniAppID)
    case interrupted(String?)
    case failure(String)
}

public enum MiniAppCaptureFailure: Error, Sendable, Equatable {
    case wrongOwner
    case featureConsentDenied(MiniAppCaptureResource)
    case osPermissionDenied(MiniAppCaptureResource)
    case missingAudioHook
    case cameraInUse(by: MiniAppID)
    case switchFailed(owner: MiniAppID, reason: String)
    case stopped
    case staleGeneration
    case unsupported
    case unavailable(String)
    case native(String)
}

public enum MiniAppCaptureState: Sendable, Equatable {
    case idle
    case requesting(Set<MiniAppCaptureResource>)
    case starting
    case running(Set<MiniAppCaptureResource>)
    case stopping(MiniAppCaptureStopReason)
    case suspended(MiniAppCaptureStopReason)
    case failed(MiniAppCaptureFailure)
    case stopped
}

@MainActor
public protocol MiniAppCapturePermissionClient: AnyObject {
    func request(_ resource: MiniAppCaptureResource) async -> Bool
}

/// A Feature-owned native producer. The closure must create and use SDK objects
/// on its own declared isolation context and return only after native start has
/// completed. Its stop closure must return only after the producer has stopped.
public struct MiniAppCaptureOperation: Sendable {
    public typealias Stop = @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    public typealias Start = @MainActor @Sendable () async throws -> Stop
    public typealias AcquireAudio = @MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void)

    public let resources: Set<MiniAppCaptureResource>
    public let startNative: Start
    public let acquireAudio: AcquireAudio?

    public init(
        resources: Set<MiniAppCaptureResource>,
        acquireAudio: AcquireAudio? = nil,
        startNative: @escaping Start
    ) {
        precondition(resources.contains(.camera), "Capture operations require camera ownership.")
        self.resources = resources
        self.acquireAudio = acquireAudio
        self.startNative = startNative
    }
}

/// Process-shared camera arbitration. Use one native-default instance for the
/// app process; tests may inject an independent instance. Microphone ownership
/// intentionally isn't represented here.
@MainActor
public final class MiniAppCaptureCoordinator {
    public static let shared = MiniAppCaptureCoordinator()

    private struct Reservation {
        let generation: UUID
        let stopProducer: @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    }

    private var reservations: [MiniAppID: Reservation] = [:]
    private var cameraOwner: MiniAppID?
    private var transition: Task<Void, Never>?

    public init() {}

    public var currentCameraOwner: MiniAppID? { cameraOwner }

    /// Serializes acquisition with an in-flight explicit switch. A rejected
    /// request never invokes another owner's stop callback.
    func reserveCamera(
        owner: MiniAppID,
        generation: UUID,
        switching: MiniAppCaptureSwitch,
        stopProducer: @escaping @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    ) async throws {
        if let transition { await transition.value }
        if cameraOwner == owner {
            reservations[owner] = Reservation(generation: generation, stopProducer: stopProducer)
            return
        }
        if let occupied = cameraOwner {
            guard switching == .stopCurrent, let reservation = reservations[occupied]
            else { throw MiniAppCaptureFailure.cameraInUse(by: occupied) }
            let task = Task { @MainActor in
                await reservation.stopProducer(.switched(to: owner))
            }
            transition = task
            await task.value
            transition = nil
            guard cameraOwner == nil else {
                throw MiniAppCaptureFailure.switchFailed(owner: occupied, reason: "producer did not release camera")
            }
        }
        cameraOwner = owner
        reservations[owner] = Reservation(generation: generation, stopProducer: stopProducer)
    }

    func releaseCamera(owner: MiniAppID, generation: UUID) {
        guard cameraOwner == owner, reservations[owner]?.generation == generation else { return }
        reservations[owner] = nil
        cameraOwner = nil
    }
}
