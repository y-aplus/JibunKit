import Foundation

@MainActor
protocol MiniAppBackgroundAssertionProviding: AnyObject {
    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> (@MainActor @Sendable () -> Void)?
}

/// Owns UIKit background-time assertions for one Feature. The time budget is
/// still shared by the host process; this type only balances native tokens.
@MainActor
public final class MiniAppBackgroundExecution {
    public enum Failure: Error { case closed }

    private struct Entry {
        let state: MiniAppBackgroundExecutionLease.State
        let endNative: @MainActor @Sendable () -> Void
        let expirationCleanup: @MainActor @Sendable () -> Void
    }

    public let ownerIdentifier: String
    public private(set) var isClosed = false
    public var activeOperationCount: Int { entries.count }

    private let provider: any MiniAppBackgroundAssertionProviding
    private var entries: [UUID: Entry] = [:]
    private var registrationsInProgress: Set<UUID> = []
    private var expirationsBeforeRegistration: Set<UUID> = []

    init(context: MiniAppContext, provider: any MiniAppBackgroundAssertionProviding) {
        ownerIdentifier = context.id.storageNamespace
        self.provider = provider
    }

    /// Returns nil when UIKit cannot grant an assertion. Start important work
    /// only after receiving a lease.
    public func begin(
        operation: String,
        onExpiration: @escaping @MainActor @Sendable () -> Void = {}
    ) throws -> MiniAppBackgroundExecutionLease? {
        guard !isClosed else { throw Failure.closed }
        let id = UUID()
        let state = MiniAppBackgroundExecutionLease.State()
        let nativeName = "jibunkit.\(ownerIdentifier).\(operation)"
        registrationsInProgress.insert(id)
        guard let endNative = provider.begin(name: nativeName, expiration: { [weak self] in
            self?.expire(id)
        }) else {
            registrationsInProgress.remove(id)
            expirationsBeforeRegistration.remove(id)
            return nil
        }

        registrationsInProgress.remove(id)
        entries[id] = Entry(
            state: state, endNative: endNative, expirationCleanup: onExpiration)
        let lease = MiniAppBackgroundExecutionLease(id: id, owner: self, state: state)
        if expirationsBeforeRegistration.remove(id) != nil { finish(id, expired: true) }
        return lease
    }

    public func endAll() {
        guard !isClosed else { return }
        isClosed = true
        for id in Array(entries.keys) { finish(id, expired: false) }
    }

    fileprivate func finish(_ id: UUID, expired: Bool) {
        guard let entry = entries.removeValue(forKey: id) else {
            if expired, registrationsInProgress.contains(id) {
                expirationsBeforeRegistration.insert(id)
            }
            return
        }
        entry.state.isEnded = true
        entry.state.didExpire = expired
        if expired { entry.expirationCleanup() }
        entry.endNative()
    }

    private func expire(_ id: UUID) { finish(id, expired: true) }

    deinit {
        let remaining = entries.values.map(\.endNative)
        Task { @MainActor in remaining.forEach { $0() } }
    }
}

@MainActor
public final class MiniAppBackgroundExecutionLease {
    @MainActor
    fileprivate final class State {
        var isEnded = false
        var didExpire = false
    }

    private let id: UUID
    private weak var owner: MiniAppBackgroundExecution?
    private let state: State

    fileprivate init(id: UUID, owner: MiniAppBackgroundExecution, state: State) {
        self.id = id
        self.owner = owner
        self.state = state
    }

    public var isEnded: Bool { state.isEnded }
    public var didExpire: Bool { state.didExpire }

    /// Idempotent. Only this operation's native assertion is ended.
    public func end() { owner?.finish(id, expired: false) }

    deinit {
        let id = id
        let owner = owner
        Task { @MainActor in owner?.finish(id, expired: false) }
    }
}

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
private final class UIApplicationBackgroundAssertionProvider: MiniAppBackgroundAssertionProviding {
    private let application: UIApplication

    init(application: UIApplication) { self.application = application }

    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> (@MainActor @Sendable () -> Void)? {
        let identifier = application.beginBackgroundTask(withName: name, expirationHandler: expiration)
        guard identifier != .invalid else { return nil }
        return { [application] in application.endBackgroundTask(identifier) }
    }
}

public extension MiniAppBackgroundExecution {
    convenience init(context: MiniAppContext, application: UIApplication = .shared) {
        self.init(context: context, provider: UIApplicationBackgroundAssertionProvider(application: application))
    }
}
#endif
