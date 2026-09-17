import Foundation

public struct MiniAppExternalContainer: Hashable, Sendable {
    public enum Database: String, Hashable, Sendable { case privateDatabase, sharedDatabase, publicDatabase }
    public let identifier: String
    public let database: Database

    public init(identifier: String, database: Database = .privateDatabase) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MiniAppExternalIdentityError.invalidIdentity
        }
        self.identifier = identifier
        self.database = database
    }
}

/// The complete ownership boundary for one external account generation.
/// `accountIdentifier` is backend supplied and must not be displayed as a user name.
public struct MiniAppExternalAccount: Hashable, Sendable {
    public let owner: MiniAppID
    public let container: MiniAppExternalContainer
    public let accountIdentifier: String
    public let generation: UUID

    public init(owner: MiniAppID, container: MiniAppExternalContainer,
                accountIdentifier: String, generation: UUID = UUID()) throws {
        guard owner.isValid, !accountIdentifier.isEmpty else { throw MiniAppExternalIdentityError.invalidIdentity }
        self.owner = owner; self.container = container
        self.accountIdentifier = accountIdentifier; self.generation = generation
    }
}

/// A Feature-local ID is never sent to a backend without the owner/account namespace.
public struct MiniAppExternalRecordIdentity: Hashable, Sendable {
    public let account: MiniAppExternalAccount
    public let localID: String

    public init(account: MiniAppExternalAccount, localID: String) throws {
        guard !localID.isEmpty else { throw MiniAppExternalIdentityError.invalidIdentity }
        self.account = account; self.localID = localID
    }

    public var zoneName: String { "jibunkit.\(account.owner.storageNamespace)" }
    public var recordName: String { Self.encode(localID) }
    public var subscriptionID: String { "jibunkit.\(account.owner.storageNamespace).changes" }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
    }
}

public struct MiniAppExternalRecord: Equatable, Sendable {
    public let identity: MiniAppExternalRecordIdentity
    public let fields: [String: String]
    public init(identity: MiniAppExternalRecordIdentity, fields: [String: String]) {
        self.identity = identity; self.fields = fields
    }
}

public enum MiniAppExternalIdentityError: Error, Equatable, Sendable {
    case invalidIdentity
    case inactive
    case accountUnavailable
    case staleGeneration
    case backend(String)
}

/// Narrow data boundary, deliberately not a general synchronization engine.
public protocol MiniAppExternalIdentityBackend: Sendable {
    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord?
    func save(_ record: MiniAppExternalRecord) async throws
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws
    func ensureSubscription(for account: MiniAppExternalAccount) async throws
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws
    func cancelOperations(owner: MiniAppID) async
}

/// One instance belongs to one Feature. Awaited backend results are committed only
/// while the exact activation/account generation is still current.
public actor MiniAppExternalIdentityCoordinator {
    public let owner: MiniAppID
    public let container: MiniAppExternalContainer
    private let backend: any MiniAppExternalIdentityBackend
    private var activation = UUID()
    private var current: MiniAppExternalAccount?

    public init(owner: MiniAppID, container: MiniAppExternalContainer,
                backend: any MiniAppExternalIdentityBackend) {
        precondition(owner.isValid)
        self.owner = owner; self.container = container; self.backend = backend
    }

    @discardableResult
    public func activate() async throws -> MiniAppExternalAccount {
        let request = activation
        let identifier: String
        do { identifier = try await backend.currentAccountIdentifier(in: container) }
        catch { throw MiniAppExternalIdentityError.backend(String(describing: error)) }
        guard request == activation else { throw MiniAppExternalIdentityError.staleGeneration }
        guard !identifier.isEmpty else { throw MiniAppExternalIdentityError.accountUnavailable }
        if let current, current.accountIdentifier == identifier { return current }
        await backend.cancelOperations(owner: owner)
        guard request == activation else { throw MiniAppExternalIdentityError.staleGeneration }
        let next = try MiniAppExternalAccount(owner: owner, container: container,
                                              accountIdentifier: identifier)
        current = next
        do { try await backend.ensureSubscription(for: next) }
        catch {
            guard current == next else { throw MiniAppExternalIdentityError.staleGeneration }
            current = nil
            throw MiniAppExternalIdentityError.backend(String(describing: error))
        }
        guard current == next else { throw MiniAppExternalIdentityError.staleGeneration }
        return next
    }

    /// Re-reads the native account. A change invalidates every handle from the old account.
    @discardableResult
    public func accountDidChange() async throws -> MiniAppExternalAccount {
        activation = UUID(); current = nil
        await backend.cancelOperations(owner: owner)
        return try await activate()
    }

    public func identity(localID: String) throws -> MiniAppExternalRecordIdentity {
        guard let current else { throw MiniAppExternalIdentityError.inactive }
        return try MiniAppExternalRecordIdentity(account: current, localID: localID)
    }

    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity)
        let expected = current
        do {
            let value = try await backend.load(identity)
            guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
            return value
        } catch {
            guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
            if let error = error as? MiniAppExternalIdentityError { throw error }
            throw MiniAppExternalIdentityError.backend(String(describing: error))
        }
    }

    public func save(_ identity: MiniAppExternalRecordIdentity, fields: [String: String]) async throws {
        try validate(identity); let expected = current
        do { try await backend.save(.init(identity: identity, fields: fields)) }
        catch {
            guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
            throw MiniAppExternalIdentityError.backend(String(describing: error))
        }
        guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
    }

    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity); let expected = current
        do { try await backend.delete(identity) }
        catch {
            guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
            throw MiniAppExternalIdentityError.backend(String(describing: error))
        }
        guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
    }

    /// Removes only this owner's zone/account generation. Other owners are not enumerable here.
    public func removeOwnedData() async throws {
        guard let expected = current else { throw MiniAppExternalIdentityError.inactive }
        do { try await backend.deleteOwnedData(for: expected) }
        catch {
            guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
            throw MiniAppExternalIdentityError.backend(String(describing: error))
        }
        guard current == expected else { throw MiniAppExternalIdentityError.staleGeneration }
    }

    public func deactivate() async {
        activation = UUID(); current = nil
        await backend.cancelOperations(owner: owner)
    }

    public func connect(to runtime: MiniAppRuntime) async throws {
        _ = try await activate()
        try await MainActor.run {
            try runtime.onShutdownAsync { [weak self] in await self?.deactivate() }
        }
    }

    private func validate(_ identity: MiniAppExternalRecordIdentity) throws {
        guard identity.account.owner == owner,
              identity.account.container == container else { throw MiniAppExternalIdentityError.invalidIdentity }
        guard identity.account == current else { throw MiniAppExternalIdentityError.staleGeneration }
    }
}

/// Safe diagnostic default. It performs no OS communication and must never be
/// reported as a successful CloudKit connection.
public struct UnavailableExternalIdentityBackend: MiniAppExternalIdentityBackend {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        throw MiniAppExternalIdentityError.backend(reason)
    }
    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? { throw failure }
    public func save(_ record: MiniAppExternalRecord) async throws { throw failure }
    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws { throw failure }
    public func ensureSubscription(for account: MiniAppExternalAccount) async throws { throw failure }
    public func deleteOwnedData(for account: MiniAppExternalAccount) async throws { throw failure }
    public func cancelOperations(owner: MiniAppID) async {}
    private var failure: MiniAppExternalIdentityError { .backend(reason) }
}
