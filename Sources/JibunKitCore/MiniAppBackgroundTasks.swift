import Foundation

public enum MiniAppBackgroundTaskKind: Equatable, Sendable {
    case appRefresh
    case processing
}

public struct MiniAppBackgroundTaskRequest: Equatable, Sendable {
    public let identifier: String
    public let earliestBeginDate: Date?
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool

    public init(
        identifier: String,
        earliestBeginDate: Date? = nil,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false
    ) {
        self.identifier = identifier
        self.earliestBeginDate = earliestBeginDate
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
    }
}

@MainActor
protocol MiniAppBackgroundTaskNative: AnyObject {
    var expirationHandler: (@MainActor @Sendable () -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol MiniAppBackgroundTaskScheduling: AnyObject {
    func register(
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void
    ) -> Bool
    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws
    func cancel(identifier: String)
}

enum MiniAppBackgroundTaskActorBridge {
    nonisolated static func deliverExpiration(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor in handler() }
    }
}

/// One OS-launched task. The host center retains this execution until
/// `complete(success:)`, including after the OS clears its expiration handler.
/// Feature work may retain it too, but must eventually complete it; dropping
/// the launch-handler argument does not imply success. Expiration and
/// completion are each delivered at most once.
@MainActor
public final class MiniAppBackgroundTaskExecution {
    public let identifier: String
    public private(set) var isExpired = false
    public private(set) var isCompleted = false
    public var onExpiration: (@MainActor () -> Void)?

    private let native: any MiniAppBackgroundTaskNative
    private var releaseFromCenter: (@MainActor () -> Void)?

    fileprivate init(
        identifier: String,
        native: any MiniAppBackgroundTaskNative,
        releaseFromCenter: @escaping @MainActor () -> Void
    ) {
        self.identifier = identifier
        self.native = native
        self.releaseFromCenter = releaseFromCenter
        native.expirationHandler = { [weak self] in self?.expire() }
    }

    /// Returns false after the first completion and never completes the native
    /// task twice. Call this after work or expiration cleanup has finished.
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
        guard !isExpired, !isCompleted else { return }
        isExpired = true
        onExpiration?()
    }
}

/// Host-shared registration boundary. Create owner handles during launch and
/// register every permitted native identifier before launch finishes.
@MainActor
public final class MiniAppBackgroundTaskCenter {
    public enum Failure: Error, Equatable {
        case invalidIdentifier
        case identifierAlreadyRegistered
        case nativeRegistrationRejected
        case identifierNotOwned
        case unsupportedRequestOptions
    }

    private struct Registration {
        let owner: String
        let kind: MiniAppBackgroundTaskKind
    }

    private let scheduler: any MiniAppBackgroundTaskScheduling
    private var registrations: [String: Registration] = [:]
    private var inFlight: [UUID: MiniAppBackgroundTaskExecution] = [:]

    init(scheduler: any MiniAppBackgroundTaskScheduling) {
        self.scheduler = scheduler
    }

    public func tasks(for context: MiniAppContext) -> MiniAppBackgroundTasks {
        MiniAppBackgroundTasks(owner: context.id.storageNamespace, center: self)
    }

    fileprivate func register(
        owner: String,
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        handler: @escaping @MainActor (MiniAppBackgroundTaskExecution) -> Void
    ) throws {
        guard !identifier.isEmpty else { throw Failure.invalidIdentifier }
        guard registrations[identifier] == nil else { throw Failure.identifierAlreadyRegistered }
        let accepted = scheduler.register(identifier: identifier, kind: kind) { [weak self] native in
            guard let self else { return }
            let executionID = UUID()
            let execution = MiniAppBackgroundTaskExecution(
                identifier: identifier,
                native: native,
                releaseFromCenter: { [weak self] in self?.inFlight.removeValue(forKey: executionID) }
            )
            inFlight[executionID] = execution
            handler(execution)
        }
        guard accepted else { throw Failure.nativeRegistrationRejected }
        registrations[identifier] = Registration(owner: owner, kind: kind)
    }

    fileprivate func submit(owner: String, request: MiniAppBackgroundTaskRequest) throws {
        guard let registration = registrations[request.identifier], registration.owner == owner else {
            throw Failure.identifierNotOwned
        }
        if registration.kind == .appRefresh,
           request.requiresNetworkConnectivity || request.requiresExternalPower {
            throw Failure.unsupportedRequestOptions
        }
        try scheduler.submit(request, kind: registration.kind)
    }

    fileprivate func cancel(owner: String, identifier: String) throws {
        guard registrations[identifier]?.owner == owner else { throw Failure.identifierNotOwned }
        scheduler.cancel(identifier: identifier)
    }

    fileprivate func cancelAll(owner: String) {
        for (identifier, registration) in registrations where registration.owner == owner {
            scheduler.cancel(identifier: identifier)
        }
    }
}

/// Owner-limited view of the host's shared BackgroundTasks registrations.
@MainActor
public final class MiniAppBackgroundTasks {
    public let ownerIdentifier: String
    private let center: MiniAppBackgroundTaskCenter

    fileprivate init(owner: String, center: MiniAppBackgroundTaskCenter) {
        ownerIdentifier = owner
        self.center = center
    }

    public func register(
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        handler: @escaping @MainActor (MiniAppBackgroundTaskExecution) -> Void
    ) throws {
        try center.register(owner: ownerIdentifier, identifier: identifier, kind: kind, handler: handler)
    }

    public func submit(_ request: MiniAppBackgroundTaskRequest) throws {
        try center.submit(owner: ownerIdentifier, request: request)
    }

    public func cancel(identifier: String) throws {
        try center.cancel(owner: ownerIdentifier, identifier: identifier)
    }

    public func cancelAllPendingRequests() {
        center.cancelAll(owner: ownerIdentifier)
    }
}
