import Foundation

public struct MiniAppLiveActivityDescriptor<Content: Sendable>: Sendable {
    public let identity: MiniAppContinuingIdentity
    public let systemID: String
    public let content: Content

    public init(identity: MiniAppContinuingIdentity, systemID: String, content: Content) {
        self.identity = identity
        self.systemID = systemID
        self.content = content
    }
}

public struct MiniAppLiveActivityNativeRecord: Equatable, Sendable {
    public enum State: Hashable, Sendable { case active, stale, ended, dismissed }
    public let identity: MiniAppContinuingIdentity
    public let systemID: String
    public let state: State

    public init(identity: MiniAppContinuingIdentity, systemID: String, state: State) {
        self.identity = identity
        self.systemID = systemID
        self.state = state
    }
}

public enum MiniAppLiveActivityError: Error, Equatable, Sendable {
    case invalidIdentity
    case staleIdentity
    case missingRegistration
    case duplicateRegistration
    case nativeStateUnresolved(systemID: String)
}

/// Typed native boundary. Feature modules keep their concrete ContentState and
/// ActivityAttributes; Core never serializes or interprets that payload.
public protocol MiniAppLiveActivityNativeDriver<Content>: Sendable {
    associatedtype Content: Sendable
    func request(identity: MiniAppContinuingIdentity, content: Content) async throws -> String
    func records() async -> [MiniAppLiveActivityNativeRecord]
    func update(systemID: String, content: Content) async
    func end(systemID: String, finalContent: Content, immediately: Bool) async
    func awaitState(systemID: String, accepted: Set<MiniAppLiveActivityNativeRecord.State>) async -> Bool
}

/// Injectable journal boundary. Production uses `MiniAppContinuingJournal`;
/// tests can exercise interruption and save failures without impersonating iOS.
public struct MiniAppLiveActivityJournalAccess: Sendable {
    public let read: @Sendable () throws -> [MiniAppContinuingRegistration]
    public let update: @Sendable (@Sendable (inout [MiniAppContinuingRegistration]) throws -> Void) throws -> Void

    public init(
        read: @escaping @Sendable () throws -> [MiniAppContinuingRegistration],
        update: @escaping @Sendable (@Sendable (inout [MiniAppContinuingRegistration]) throws -> Void) throws -> Void
    ) {
        self.read = read
        self.update = update
    }
}

#if os(iOS) || os(macOS)
public extension MiniAppLiveActivityJournalAccess {
    init(_ journal: MiniAppContinuingJournal) {
        self.init(read: { try journal.read() }, update: { mutation in try journal.update(mutation) })
    }
}
#endif

/// One instance must be shared by the app process, including LiveActivityIntent.
/// The gate remains occupied across every native suspension, preventing actor
/// reentrancy from admitting a duplicate request.
public struct MiniAppLiveActivityCoordinator<Driver: MiniAppLiveActivityNativeDriver>: Sendable {
    public typealias Content = Driver.Content
    public typealias Admission = @Sendable (MiniAppContinuingIdentity) async throws -> Void

    private let owner: MiniAppID
    private let gate: MiniAppContinuingOperationGate
    private let journal: MiniAppLiveActivityJournalAccess
    private let native: Driver
    private let admission: Admission

    public init(owner: MiniAppID, gate: MiniAppContinuingOperationGate,
                journal: MiniAppLiveActivityJournalAccess, native: Driver,
                admission: @escaping Admission) {
        precondition(owner.isValid)
        self.owner = owner
        self.gate = gate
        self.journal = journal
        self.native = native
        self.admission = admission
    }

    public func start(identity: MiniAppContinuingIdentity, content: Content) async throws
        -> MiniAppLiveActivityDescriptor<Content> {
        try await gate.perform { [self] in
            try await validate(identity)
            let registrations = try journal.read()
            if let existing = registrations.first(where: { $0.identity == identity && $0.phase != .ending }) {
                guard let systemID = existing.systemID else { throw MiniAppLiveActivityError.duplicateRegistration }
                return .init(identity: identity, systemID: systemID, content: content)
            }
            try journal.update { rows in
                rows.append(.init(identity: identity, phase: .starting))
            }
            // A throwing request intentionally leaves the starting row. A later
            // reconcile can discover an OS-success/process-interruption gap.
            let systemID = try await native.request(identity: identity, content: content)
            try journal.update { rows in
                guard let index = rows.firstIndex(where: { $0.identity == identity }) else {
                    throw MiniAppLiveActivityError.missingRegistration
                }
                rows[index].systemID = systemID
                rows[index].phase = .active
            }
            return .init(identity: identity, systemID: systemID, content: content)
        }
    }

    public func update(_ descriptor: MiniAppLiveActivityDescriptor<Content>, content: Content) async throws
        -> MiniAppLiveActivityDescriptor<Content> {
        try await gate.perform { [self] in
            try await validate(descriptor.identity)
            try requireActive(descriptor.identity, systemID: descriptor.systemID)
            await native.update(systemID: descriptor.systemID, content: content)
            guard await native.awaitState(systemID: descriptor.systemID, accepted: [.active, .stale]) else {
                throw MiniAppLiveActivityError.nativeStateUnresolved(systemID: descriptor.systemID)
            }
            return .init(identity: descriptor.identity, systemID: descriptor.systemID, content: content)
        }
    }

    public func end(_ descriptor: MiniAppLiveActivityDescriptor<Content>, finalContent: Content,
                    immediately: Bool = false) async throws {
        try await gate.perform { [self] in
            try await validate(descriptor.identity)
            try requireActive(descriptor.identity, systemID: descriptor.systemID)
            try markEnding(descriptor.identity, systemID: descriptor.systemID)
            await native.end(systemID: descriptor.systemID, finalContent: finalContent, immediately: immediately)
            let accepted: Set<MiniAppLiveActivityNativeRecord.State> = immediately ? [.dismissed] : [.ended, .dismissed]
            guard await native.awaitState(systemID: descriptor.systemID, accepted: accepted) else {
                throw MiniAppLiveActivityError.nativeStateUnresolved(systemID: descriptor.systemID)
            }
            try remove(descriptor.identity)
        }
    }

    /// Repairs exact typed bindings and removes only terminal saved rows. Unknown
    /// OS rows remain diagnostics; they are never attributed to another owner.
    public func reconcile() async throws {
        try await gate.performMaintenance { [self] in
            let os = await native.records()
            let owned = os.filter { $0.identity.owner == owner.rawValue }
            let savedBeforeRepair = try journal.read()
            for saved in savedBeforeRepair {
                let duplicates = owned.filter {
                    $0.identity == saved.identity && $0.state != .dismissed
                }
                // Reconcile has no authority to invent Feature final content.
                // Preserve every row and surface the collision for endOwned,
                // whose caller supplies typed final content.
                if duplicates.count > 1 { throw MiniAppLiveActivityError.duplicateRegistration }
            }
            try journal.update { rows in
                var repaired: [MiniAppContinuingRegistration] = []
                for var saved in rows {
                    guard saved.identity.owner == owner.rawValue else {
                        repaired.append(saved)
                        continue
                    }
                    if let match = owned.first(where: { $0.identity == saved.identity }) {
                        if match.state == .dismissed { continue }
                        if saved.systemID == nil {
                            saved.systemID = match.systemID
                        }
                        saved.phase = match.state == .ended ? .ending : .active
                        repaired.append(saved)
                    }
                }
                rows = repaired
            }
        }
    }

    public func close() async { await gate.close() }
    public func open() async { await gate.open() }

    /// Cleanup does not consult SharedState/admission. Concrete typed attributes
    /// prove ownership; foreign-owner and other Feature records are untouched.
    public func endOwned(finalContent: @escaping @Sendable (MiniAppContinuingIdentity) -> Content) async throws {
        try await gate.performMaintenance { [self] in
            let owned = await native.records().filter { $0.identity.owner == owner.rawValue }
            for record in owned where record.state != .dismissed {
                try markEndingIfSaved(record.identity, systemID: record.systemID)
                await native.end(systemID: record.systemID, finalContent: finalContent(record.identity), immediately: true)
                guard await native.awaitState(systemID: record.systemID, accepted: [.dismissed]) else {
                    throw MiniAppLiveActivityError.nativeStateUnresolved(systemID: record.systemID)
                }
                try remove(record.identity)
            }
            // Starting rows without an OS match are retained for later reconcile.
        }
    }

    public func surface(id: String,
        finalContent: @escaping @Sendable (MiniAppContinuingIdentity) -> Content) -> MiniAppContinuingSurface {
        MiniAppContinuingSurface(owner: owner, id: id,
            close: { await self.close() }, reconcile: { try await self.reconcile() },
            endOwned: { try await self.endOwned(finalContent: finalContent) }, open: { await self.open() })
    }

    private func validate(_ identity: MiniAppContinuingIdentity) async throws {
        guard identity.owner == owner.rawValue, !identity.localID.isEmpty else {
            throw MiniAppLiveActivityError.invalidIdentity
        }
        try await admission(identity)
    }

    private func requireActive(_ identity: MiniAppContinuingIdentity, systemID: String) throws {
        guard try journal.read().contains(where: {
            $0.identity == identity && $0.systemID == systemID && $0.phase == .active
        }) else { throw MiniAppLiveActivityError.staleIdentity }
    }

    private func markEnding(_ identity: MiniAppContinuingIdentity, systemID: String) throws {
        try journal.update { rows in
            guard let index = rows.firstIndex(where: { $0.identity == identity && $0.systemID == systemID && $0.phase == .active })
            else { throw MiniAppLiveActivityError.staleIdentity }
            rows[index].phase = .ending
        }
    }

    private func markEndingIfSaved(_ identity: MiniAppContinuingIdentity, systemID: String) throws {
        try journal.update { rows in
            if let index = rows.firstIndex(where: { $0.identity == identity && ($0.systemID == nil || $0.systemID == systemID) }) {
                rows[index].systemID = systemID
                rows[index].phase = .ending
            }
        }
    }

    private func remove(_ identity: MiniAppContinuingIdentity) throws {
        try journal.update { $0.removeAll { $0.identity == identity } }
    }

}
