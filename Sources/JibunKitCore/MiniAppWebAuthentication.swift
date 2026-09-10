import Foundation

@MainActor
protocol MiniAppWebAuthenticationSession: AnyObject {
    func start() -> Bool
    func cancel()
}

@MainActor
protocol MiniAppWebAuthenticationSessionProviding: AnyObject {
    func makeSession(
        url: URL,
        callbackURLScheme: String?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) -> any MiniAppWebAuthenticationSession
}

/// Serializes a host-selected presentation surface while retaining request
/// ownership and completion routing for the Feature that started it.
/// Separate surfaces may use separate coordinators.
@MainActor
public final class MiniAppWebAuthenticationCoordinator {
    public enum Failure: Error, Equatable {
        case presentationBusy(owner: MiniAppID)
        case startRejected
        case cancelled
        case missingCallbackURL
    }

    private struct Active {
        let id: UUID
        let connectionID: UUID
        let owner: MiniAppID
        let provider: any MiniAppWebAuthenticationSessionProviding
        let session: any MiniAppWebAuthenticationSession
        let state: MiniAppWebAuthenticationRequest.State
        let completion: @MainActor (Result<URL, Error>) -> Void
    }

    private var active: Active?

    public init() {}

    public var activeOwner: MiniAppID? { active?.owner }

    fileprivate func start(
        connectionID: UUID,
        owner: MiniAppID,
        url: URL,
        callbackURLScheme: String?,
        provider: any MiniAppWebAuthenticationSessionProviding,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) throws -> MiniAppWebAuthenticationRequest {
        if let active { throw Failure.presentationBusy(owner: active.owner) }
        let id = UUID()
        let state = MiniAppWebAuthenticationRequest.State()
        let session = provider.makeSession(url: url, callbackURLScheme: callbackURLScheme) {
            [weak self] result in self?.finish(id: id, result: result, cancelNative: false)
        }
        active = Active(
            id: id, connectionID: connectionID, owner: owner, provider: provider, session: session,
            state: state, completion: completion)
        let request = MiniAppWebAuthenticationRequest(id: id, coordinator: self, state: state)
        if !session.start(), active?.id == id {
            finish(id: id, result: .failure(Failure.startRejected), cancelNative: false)
        }
        return request
    }

    fileprivate func cancel(id: UUID) {
        finish(id: id, result: .failure(Failure.cancelled), cancelNative: true)
    }

    fileprivate func cancel(connectionID: UUID) {
        guard active?.connectionID == connectionID, let id = active?.id else { return }
        cancel(id: id)
    }

    private func finish(id: UUID, result: Result<URL, Error>, cancelNative: Bool) {
        guard let entry = active, entry.id == id else { return }
        active = nil
        entry.state.isFinished = true
        if cancelNative { entry.session.cancel() }
        entry.completion(result)
    }
}

@MainActor
public final class MiniAppWebAuthenticationRequest {
    @MainActor fileprivate final class State { var isFinished = false }
    private let id: UUID
    private weak var coordinator: MiniAppWebAuthenticationCoordinator?
    private let state: State

    fileprivate init(id: UUID, coordinator: MiniAppWebAuthenticationCoordinator, state: State) {
        self.id = id
        self.coordinator = coordinator
        self.state = state
    }

    public var isFinished: Bool { state.isFinished }
    public func cancel() { coordinator?.cancel(id: id) }

    deinit {
        let id = id
        let coordinator = coordinator
        Task { @MainActor in coordinator?.cancel(id: id) }
    }
}

@MainActor
public final class MiniAppWebAuthentication {
    public let owner: MiniAppID
    let connectionID = UUID()
    let coordinator: MiniAppWebAuthenticationCoordinator
    private let provider: any MiniAppWebAuthenticationSessionProviding
    private var isClosed = false

    init(
        context: MiniAppContext,
        coordinator: MiniAppWebAuthenticationCoordinator,
        provider: any MiniAppWebAuthenticationSessionProviding
    ) {
        owner = context.id
        self.coordinator = coordinator
        self.provider = provider
    }

    public func start(
        url: URL,
        callbackURLScheme: String?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) throws -> MiniAppWebAuthenticationRequest {
        guard !isClosed else { throw MiniAppRuntime.Failure.closed }
        return try coordinator.start(
            connectionID: connectionID, owner: owner, url: url,
            callbackURLScheme: callbackURLScheme,
            provider: provider, completion: completion)
    }

    func start(
        url: URL,
        provider: any MiniAppWebAuthenticationSessionProviding,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) throws -> MiniAppWebAuthenticationRequest {
        guard !isClosed else { throw MiniAppRuntime.Failure.closed }
        return try coordinator.start(
            connectionID: connectionID, owner: owner, url: url,
            callbackURLScheme: nil, provider: provider, completion: completion)
    }

    public func cancel() { coordinator.cancel(connectionID: connectionID) }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        cancel()
    }
}
