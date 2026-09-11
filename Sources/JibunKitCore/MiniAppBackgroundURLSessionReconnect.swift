import Foundation

public struct MiniAppBackgroundURLSessionIdentifier: Hashable, Sendable {
    public enum Failure: Error, Equatable { case invalidProfile, invalidIdentifier }

    public static let prefix = "jibunkit.background.v1"
    public let rawValue: String
    public let owner: MiniAppID
    public let profile: String

    public init(context: MiniAppContext, profile: String) throws {
        guard !profile.isEmpty else { throw Failure.invalidProfile }
        owner = context.id
        self.profile = profile
        rawValue = [Self.prefix, Self.encode(context.id.rawValue), Self.encode(profile)]
            .joined(separator: ".")
    }

    public init(rawValue: String) throws {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 5,
              components[0] == "jibunkit",
              components[1] == "background",
              components[2] == "v1",
              let ownerValue = Self.decode(String(components[3])),
              let profile = Self.decode(String(components[4])),
              !profile.isEmpty
        else { throw Failure.invalidIdentifier }
        let owner = MiniAppID(ownerValue)
        guard owner.isValid else { throw Failure.invalidIdentifier }
        self.rawValue = rawValue
        self.owner = owner
        self.profile = profile
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8)
        else { return nil }
        return decoded
    }
}

public extension MiniAppContext {
    func backgroundURLSessionIdentifier(profile: String) throws -> String {
        try MiniAppBackgroundURLSessionIdentifier(context: self, profile: profile).rawValue
    }
}

/// Owns the host completion delivered for one background URLSession callback.
/// A Feature delegate forwards urlSessionDidFinishEvents to finish().
@MainActor
public final class MiniAppBackgroundURLSessionEvents {
    private let id: UUID
    private var completions: [@MainActor @Sendable () -> Void]?
    private let didFinish: @MainActor @Sendable (UUID) -> Void

    fileprivate init(
        id: UUID,
        completion: @escaping @MainActor @Sendable () -> Void,
        didFinish: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.id = id
        completions = [completion]
        self.didFinish = didFinish
    }

    fileprivate func append(
        completion: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        guard completions != nil else { return false }
        completions?.append(completion)
        return true
    }

    /// Returns true only for the call which owns and invokes the host completion.
    @discardableResult
    public func finish() -> Bool {
        guard let completions else { return false }
        self.completions = nil
        didFinish(id)
        for completion in completions { completion() }
        return true
    }
}

/// Process-level routing for UIApplicationDelegate background URLSession events.
/// Register stable Feature/profile factories during host launch, before any UI.
/// Factories create the native background URLSession with their existing
/// delegate; this registry does not replace URLSession or delegate behavior.
@MainActor
public final class MiniAppBackgroundURLSessionReconnectRegistry {
    public enum Failure: Error, Equatable { case duplicateRegistration }
    public enum HandlingResult: Equatable {
        case connected, unknownSession, joinedPending, reconnectFailed
    }
    public typealias Reconnect = @MainActor @Sendable (
        _ identifier: String,
        _ events: MiniAppBackgroundURLSessionEvents
    ) throws -> Void

    public static let shared = MiniAppBackgroundURLSessionReconnectRegistry()

    private struct Handler {
        let registrationID: UUID
        let owner: MiniAppID
        let reconnect: Reconnect
    }

    private var handlers: [String: Handler] = [:]
    private struct Pending {
        let eventID: UUID
        let events: MiniAppBackgroundURLSessionEvents
    }

    private var pending: [String: Pending] = [:]

    public init() {}

    public func register(
        context: MiniAppContext,
        profile: String,
        reconnect: @escaping Reconnect
    ) throws -> MiniAppBackgroundURLSessionRegistration {
        let identifier = try MiniAppBackgroundURLSessionIdentifier(
            context: context,
            profile: profile
        )
        guard handlers[identifier.rawValue] == nil else {
            throw Failure.duplicateRegistration
        }
        let registrationID = UUID()
        handlers[identifier.rawValue] = Handler(
            registrationID: registrationID,
            owner: context.id,
            reconnect: reconnect
        )
        return MiniAppBackgroundURLSessionRegistration(
            registry: self,
            identifier: identifier.rawValue,
            registrationID: registrationID
        )
    }

    @discardableResult
    public func handleEvents(
        identifier rawIdentifier: String,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) -> HandlingResult {
        if let pending = pending[rawIdentifier] {
            guard pending.events.append(completion: completionHandler) else {
                completionHandler()
                return .unknownSession
            }
            return .joinedPending
        }
        guard let identifier = try? MiniAppBackgroundURLSessionIdentifier(rawValue: rawIdentifier),
              let handler = handlers[rawIdentifier],
              handler.owner == identifier.owner
        else {
            completionHandler()
            return .unknownSession
        }

        let eventID = UUID()
        let events = MiniAppBackgroundURLSessionEvents(
            id: eventID,
            completion: completionHandler,
            didFinish: { [weak self] finishedID in
                self?.finish(identifier: rawIdentifier, eventID: finishedID)
            }
        )
        pending[rawIdentifier] = Pending(eventID: eventID, events: events)
        do {
            try handler.reconnect(rawIdentifier, events)
            return .connected
        } catch {
            events.finish()
            return .reconnectFailed
        }
    }

    fileprivate func cancel(identifier: String, registrationID: UUID) {
        guard handlers[identifier]?.registrationID == registrationID else { return }
        handlers.removeValue(forKey: identifier)
    }

    private func finish(identifier: String, eventID: UUID) {
        guard pending[identifier]?.eventID == eventID else { return }
        pending.removeValue(forKey: identifier)
    }
}

@MainActor
public final class MiniAppBackgroundURLSessionRegistration {
    public let identifier: String
    private weak var registry: MiniAppBackgroundURLSessionReconnectRegistry?
    private let registrationID: UUID
    private var isCancelled = false

    fileprivate init(
        registry: MiniAppBackgroundURLSessionReconnectRegistry,
        identifier: String,
        registrationID: UUID
    ) {
        self.registry = registry
        self.identifier = identifier
        self.registrationID = registrationID
    }

    /// Removes only this Feature/profile factory. A pending callback remains
    /// owned by its delegate token until urlSessionDidFinishEvents is forwarded.
    /// Other owners and profiles remain connected.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        registry?.cancel(identifier: identifier, registrationID: registrationID)
    }

    deinit {
        let registry = registry
        let identifier = identifier
        let registrationID = registrationID
        Task { @MainActor in
            registry?.cancel(identifier: identifier, registrationID: registrationID)
        }
    }
}
