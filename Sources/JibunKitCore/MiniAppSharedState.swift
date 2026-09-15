import Foundation

#if os(iOS) || os(macOS)
public enum MiniAppSharedStateError: Error, Equatable, Sendable {
    case invalidOwner, invalidDirectory, unavailable, staleGeneration, invalidState, coordinationFailed
}

/// A small, Feature-owned Codable state shared by an app and its extensions.
/// Every writer, including management and restore, must use this same store.
/// This is an opt-in storage format, not a transaction for arbitrary databases.
public struct MiniAppSharedState<Value: Codable & Sendable>: Sendable {
    public struct Snapshot: Sendable {
        public let generation: UUID
        public let value: Value
    }

    private struct Payload: Codable {
        var value: Value
    }

    private struct Envelope: Codable {
        let format: Int
        let owner: String
        var generation: UUID
        var enabled: Bool
        var value: Payload?
    }

    public let owner: MiniAppID
    private let root: URL
    private let stateURL: URL
    private let lockURL: URL

    /// Use the same app-group container in the host and extension. The lock
    /// lives outside the owner's removable payload and must never be deleted
    /// while any process can access the store.
    public init(owner: MiniAppID, containerURL: URL) throws {
        guard owner.isValid else { throw MiniAppSharedStateError.invalidOwner }
        guard containerURL.isFileURL else { throw MiniAppSharedStateError.invalidDirectory }
        self.owner = owner
        root = containerURL.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/JibunKit/SharedState", isDirectory: true)
        stateURL = root.appendingPathComponent(owner.storageNamespace + ".json")
        lockURL = root.appendingPathComponent(owner.storageNamespace + ".lock")
    }

    public static func shared(
        owner: MiniAppID,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> Self {
        let identifier = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw MiniAppFileError.unavailableGroupContainer(identifier: identifier)
        }
        return try Self(owner: owner, containerURL: container)
    }

    /// Host-only first registration. Existing state (including a deletion
    /// tombstone) is never overwritten or silently re-enabled. A missing file
    /// is not a default value for an extension action.
    public func initialize(_ value: Value, enabled: Bool) throws {
        try coordinated {
            if FileManager.default.fileExists(atPath: stateURL.path) {
                _ = try load()
                return
            }
            try save(Envelope(format: 1, owner: owner.rawValue,
                              generation: UUID(), enabled: enabled, value: Payload(value: value)))
        }
    }

    public func read() throws -> Snapshot {
        try coordinated {
            let envelope = try load()
            guard envelope.enabled, let value = envelope.value else { throw MiniAppSharedStateError.unavailable }
            return Snapshot(generation: envelope.generation, value: value.value)
        }
    }

    /// The generation comes from a read when preparing this action. A queued
    /// old Widget action cannot modify replacement data after remove/restore.
    /// The closure is synchronous, must not reenter this store, and must not
    /// perform async work or mutate external resources expecting rollback.
    @discardableResult
    public func update<Result>(
        generation: UUID,
        _ operation: (inout Value) throws -> Result
    ) throws -> Result {
        try coordinated {
            try Task.checkCancellation()
            var envelope = try load()
            guard envelope.enabled, var value = envelope.value else { throw MiniAppSharedStateError.unavailable }
            guard envelope.generation == generation else { throw MiniAppSharedStateError.staleGeneration }
            let result = try operation(&value.value)
            try Task.checkCancellation()
            envelope.value = value
            try save(envelope)
            return result
        }
    }

    /// Waits for a currently admitted synchronous write, then closes admission
    /// under the same per-owner cross-process coordination. Re-enabling never
    /// recreates deleted data. Only the host management path calls this method.
    public func setEnabled(_ enabled: Bool) throws {
        try coordinated {
            var envelope = try load()
            guard !enabled || envelope.value != nil else { throw MiniAppSharedStateError.unavailable }
            envelope.enabled = enabled
            try save(envelope)
        }
    }

    /// Requires closed admission. Keeps a tombstone and changes generation so
    /// an old operation cannot resurrect or overwrite a re-registered owner.
    public func remove() throws {
        try coordinated {
            var envelope = try load()
            guard !envelope.enabled else { throw MiniAppSharedStateError.unavailable }
            envelope.value = nil
            envelope.generation = UUID()
            try save(envelope)
        }
    }

    /// Used by host restore/re-registration while external admission is closed.
    /// Does not reopen it: the management/lifecycle caller decides whether the
    /// Feature may resume. A corrupt prior envelope is not implicitly replaced.
    public func replaceWhileDisabled(_ value: Value) throws {
        try coordinated {
            var envelope = try load()
            guard !envelope.enabled else { throw MiniAppSharedStateError.unavailable }
            envelope.value = Payload(value: value)
            envelope.generation = UUID()
            try save(envelope)
        }
    }

    private func load() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { throw MiniAppSharedStateError.unavailable }
        let values = try stateURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MiniAppSharedStateError.invalidState }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: stateURL))
        guard envelope.format == 1, envelope.owner == owner.rawValue else { throw MiniAppSharedStateError.invalidState }
        return envelope
    }

    private func save(_ envelope: Envelope) throws {
        try JSONEncoder().encode(envelope).write(to: stateURL, options: .atomic)
    }

    private func coordinated<Result>(_ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw MiniAppSharedStateError.invalidDirectory
        }
        if FileManager.default.fileExists(atPath: lockURL.path) {
            let values = try lockURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MiniAppSharedStateError.invalidDirectory }
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Swift.Result<Result, Error>?
        coordinator.coordinate(writingItemAt: lockURL, options: [], error: &coordinationError) { _ in
            result = Swift.Result { try operation() }
        }
        if let result { return try result.get() }
        throw coordinationError ?? MiniAppSharedStateError.coordinationFailed as NSError
    }
}
#endif
