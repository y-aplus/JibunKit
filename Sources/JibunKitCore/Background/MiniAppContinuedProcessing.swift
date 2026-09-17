import Foundation

public enum MiniAppContinuedProcessingStrategy: Equatable, Sendable {
    case queue
    case fail
}

public struct MiniAppContinuedProcessingRequest: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let subtitle: String
    public let strategy: MiniAppContinuedProcessingStrategy

    public init(
        identifier: String,
        title: String,
        subtitle: String,
        strategy: MiniAppContinuedProcessingStrategy = .queue
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.strategy = strategy
    }
}

@MainActor
protocol MiniAppContinuedProcessingNative: AnyObject {
    var expirationHandler: (@MainActor @Sendable () -> Void)? { get set }
    func updateProgress(completed: Int64, total: Int64)
    func updateTitle(_ title: String, subtitle: String)
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol MiniAppContinuedProcessingScheduling: AnyObject {
    func register(
        identifier: String,
        launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void
    ) -> Bool
    func submit(_ request: MiniAppContinuedProcessingRequest) throws
    func cancel(identifier: String)
}

/// One user-initiated continued-processing job delivered by the system. The
/// Feature owns its work and checkpoints; this object owns only native progress,
/// expiration, and completion. Expiration requests cleanup and never reports
/// completion on the Feature's behalf.
@MainActor
public final class MiniAppContinuedProcessingExecution {
    public let identifier: String
    public private(set) var isExpired = false
    public private(set) var isCompleted = false
    public var onExpiration: (@MainActor () -> Void)? {
        didSet { deliverExpirationIfNeeded() }
    }

    private let native: any MiniAppContinuedProcessingNative
    private var deliveredExpiration = false
    private var releaseFromCenter: (@MainActor () -> Void)?

    fileprivate init(
        identifier: String,
        native: any MiniAppContinuedProcessingNative,
        releaseFromCenter: @escaping @MainActor () -> Void
    ) {
        self.identifier = identifier
        self.native = native
        self.releaseFromCenter = releaseFromCenter
        native.expirationHandler = { [weak self] in self?.expire() }
    }

    public func reportProgress(completed: Int64, total: Int64) {
        precondition(total > 0, "Continued-processing progress requires a positive total.")
        precondition((0...total).contains(completed), "Completed work must be within the total.")
        guard !isCompleted else { return }
        native.updateProgress(completed: completed, total: total)
    }

    public func updateTitle(_ title: String, subtitle: String) {
        guard !isCompleted else { return }
        native.updateTitle(title, subtitle: subtitle)
    }

    /// Idempotently completes exactly this native task after Feature cleanup.
    @discardableResult
    public func complete(success: Bool) -> Bool {
        guard !isCompleted else { return false }
        isCompleted = true
        native.expirationHandler = nil
        onExpiration = nil
        native.setTaskCompleted(success: success)
        let releaseFromCenter = releaseFromCenter
        self.releaseFromCenter = nil
        releaseFromCenter?()
        return true
    }

    private func expire() {
        guard !isCompleted, !isExpired else { return }
        isExpired = true
        deliverExpirationIfNeeded()
    }

    private func deliverExpirationIfNeeded() {
        guard isExpired, !isCompleted, !deliveredExpiration, let onExpiration else { return }
        deliveredExpiration = true
        onExpiration()
    }
}

/// Process-shared registration boundary for iOS 26 continued processing.
/// Register stable or fully composed permitted identifiers from the Feature's
/// normal integration point, then submit only in direct response to user action.
@MainActor
public final class MiniAppContinuedProcessingCenter {
    public enum Failure: Error, Equatable {
        case invalidIdentifier
        case invalidPresentation
        case identifierAlreadyRegistered
        case nativeRegistrationRejected
        case identifierNotOwned
    }

    private struct Registration { let owner: String }

    private let scheduler: any MiniAppContinuedProcessingScheduling
    private var registrations: [String: Registration] = [:]
    private var inFlight: [UUID: MiniAppContinuedProcessingExecution] = [:]

    init(scheduler: any MiniAppContinuedProcessingScheduling) {
        self.scheduler = scheduler
    }

    public func tasks(for context: MiniAppContext) -> MiniAppContinuedProcessingTasks {
        MiniAppContinuedProcessingTasks(owner: context.id.storageNamespace, center: self)
    }

    fileprivate func register(
        owner: String,
        identifier: String,
        handler: @escaping @MainActor (MiniAppContinuedProcessingExecution) -> Void
    ) throws {
        guard !identifier.isEmpty else { throw Failure.invalidIdentifier }
        guard registrations[identifier] == nil else { throw Failure.identifierAlreadyRegistered }
        let accepted = scheduler.register(identifier: identifier) { [weak self] native in
            guard let self else { return }
            let executionID = UUID()
            let execution = MiniAppContinuedProcessingExecution(
                identifier: identifier,
                native: native,
                releaseFromCenter: { [weak self] in self?.inFlight.removeValue(forKey: executionID) }
            )
            inFlight[executionID] = execution
            handler(execution)
        }
        guard accepted else { throw Failure.nativeRegistrationRejected }
        registrations[identifier] = Registration(owner: owner)
    }

    fileprivate func submit(owner: String, request: MiniAppContinuedProcessingRequest) throws {
        guard registrations[request.identifier]?.owner == owner else {
            throw Failure.identifierNotOwned
        }
        guard !request.title.isEmpty, !request.subtitle.isEmpty else {
            throw Failure.invalidPresentation
        }
        try scheduler.submit(request)
    }

    fileprivate func cancel(owner: String, identifier: String) throws {
        guard registrations[identifier]?.owner == owner else { throw Failure.identifierNotOwned }
        scheduler.cancel(identifier: identifier)
    }
}

/// Owner-limited view of continued-processing registrations and requests.
@MainActor
public final class MiniAppContinuedProcessingTasks {
    public let ownerIdentifier: String
    private let center: MiniAppContinuedProcessingCenter

    fileprivate init(owner: String, center: MiniAppContinuedProcessingCenter) {
        ownerIdentifier = owner
        self.center = center
    }

    public func register(
        identifier: String,
        handler: @escaping @MainActor (MiniAppContinuedProcessingExecution) -> Void
    ) throws {
        try center.register(owner: ownerIdentifier, identifier: identifier, handler: handler)
    }

    /// Call from a foreground user action. Automatic maintenance and refresh
    /// work belongs in the existing refresh/processing APIs instead.
    public func submit(_ request: MiniAppContinuedProcessingRequest) throws {
        try center.submit(owner: ownerIdentifier, request: request)
    }

    /// Cancels a queued request for this identifier. A launched execution is
    /// still completed by its Feature after cooperative cleanup.
    public func cancelPendingRequest(identifier: String) throws {
        try center.cancel(owner: ownerIdentifier, identifier: identifier)
    }
}
