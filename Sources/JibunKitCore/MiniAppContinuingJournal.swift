import Foundation

/// Full identity carried by a native surface and its actions. Registration ID
/// distinguishes replacements within one business-data generation.
public struct MiniAppContinuingIdentity: Codable, Hashable, Sendable {
    public let owner: String
    public let localID: String
    public let generation: UUID
    public let registrationID: UUID

    public init(owner: MiniAppID, localID: String, generation: UUID,
                registrationID: UUID = UUID()) throws {
        guard owner.isValid, !localID.isEmpty else { throw MiniAppContinuingError.invalidIdentity }
        self.owner = owner.rawValue
        self.localID = localID
        self.generation = generation
        self.registrationID = registrationID
    }
}

public struct MiniAppContinuingRegistration: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case starting, active, ending }
    public let identity: MiniAppContinuingIdentity
    public var systemID: String?
    public var phase: Phase

    public init(identity: MiniAppContinuingIdentity, systemID: String? = nil,
                phase: Phase = .starting) {
        self.identity = identity
        self.systemID = systemID
        self.phase = phase
    }
}

#if os(iOS) || os(macOS)
/// Minimal OS-registration bookkeeping, deliberately separate from backed-up
/// business data. It remains readable during disable/remove/restore. Never keep
/// an async OS call inside update; save intent first, then reconcile its result.
public struct MiniAppContinuingJournal: Sendable {
    private struct Envelope: Codable {
        let format: Int
        let owner: String
        let namespace: String
        var registrations: [MiniAppContinuingRegistration]
    }

    public let owner: MiniAppID
    public let namespace: String
    private let root: URL
    private let file: URL
    private let lock: URL

    public init(owner: MiniAppID, namespace: String, containerURL: URL) throws {
        guard owner.isValid, MiniAppID(namespace).isValid, containerURL.isFileURL else {
            throw MiniAppContinuingError.invalidIdentity
        }
        self.owner = owner
        self.namespace = namespace
        root = containerURL.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/JibunKit/ContinuingSurfaces", isDirectory: true)
            .appendingPathComponent(owner.storageNamespace, isDirectory: true)
        file = root.appendingPathComponent(MiniAppID(namespace).storageNamespace + ".json")
        lock = root.appendingPathComponent(MiniAppID(namespace).storageNamespace + ".lock")
    }

    public static func shared(owner: MiniAppID, namespace: String,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) throws -> Self {
        let identifier = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw MiniAppFileError.unavailableGroupContainer(identifier: identifier)
        }
        return try Self(owner: owner, namespace: namespace, containerURL: container)
    }

    public func read() throws -> [MiniAppContinuingRegistration] {
        try coordinated { try load().registrations }
    }

    /// Synchronous and non-reentrant; no external side effects in the closure.
    /// A throwing mutation or save leaves the previous journal intact. This does
    /// not reject cancellation after an OS call: its recovery record is essential.
    @discardableResult
    public func update<Value>(_ mutation: (inout [MiniAppContinuingRegistration]) throws -> Value) throws -> Value {
        try coordinated {
            var envelope = try load()
            let result = try mutation(&envelope.registrations)
            try validate(envelope)
            try JSONEncoder().encode(envelope).write(to: file, options: .atomic)
            return result
        }
    }

    private func load() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Envelope(format: 1, owner: owner.rawValue, namespace: namespace, registrations: [])
        }
        try regularFile(file)
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        try validate(envelope)
        return envelope
    }

    private func validate(_ envelope: Envelope) throws {
        guard envelope.format == 1, envelope.owner == owner.rawValue, envelope.namespace == namespace,
              Set(envelope.registrations.map { $0.identity.registrationID }).count == envelope.registrations.count,
              Set(envelope.registrations.compactMap(\.systemID)).count == envelope.registrations.compactMap(\.systemID).count,
              envelope.registrations.allSatisfy({ record in
                  record.identity.owner == owner.rawValue && !record.identity.localID.isEmpty
                      && (record.systemID == nil || record.systemID?.isEmpty == false)
                      && (record.phase != .active || record.systemID != nil)
              }) else { throw MiniAppContinuingError.invalidJournal }
    }

    private func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw MiniAppContinuingError.invalidJournal
        }
    }

    private func coordinated<Value>(_ operation: () throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw MiniAppContinuingError.invalidJournal
        }
        if FileManager.default.fileExists(atPath: lock.path) { try regularFile(lock) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        var result: Result<Value, Error>?
        coordinator.coordinate(writingItemAt: lock, options: [], error: &error) { _ in
            result = Result { try operation() }
        }
        if let result { return try result.get() }
        throw error ?? MiniAppContinuingError.coordinationFailed as NSError
    }
}
#endif
