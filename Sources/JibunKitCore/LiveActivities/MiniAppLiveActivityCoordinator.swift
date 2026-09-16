import Foundation

public struct MiniAppLiveActivityDescriptor: Equatable, Sendable {
    public let identity: MiniAppContinuingIdentity
    public let systemID: String
    public init(identity: MiniAppContinuingIdentity, systemID: String) {
        self.identity = identity; self.systemID = systemID
    }
}

public struct MiniAppLiveActivityNativeRecord: Equatable, Sendable {
    public enum State: Hashable, Sendable { case pending, active, stale, ended, dismissed, unknown }
    public let identity: MiniAppContinuingIdentity
    public let systemID: String
    public let state: State
    public init(identity: MiniAppContinuingIdentity, systemID: String, state: State) {
        self.identity = identity; self.systemID = systemID; self.state = state
    }
}

public struct MiniAppLiveActivityReconcileReport: Equatable, Sendable {
    public var unknownSystemIDs: [String]
    public var duplicateSystemIDs: [String]
    public var mismatchedSystemIDs: [String]
    public init(unknownSystemIDs: [String] = [], duplicateSystemIDs: [String] = [],
                mismatchedSystemIDs: [String] = []) {
        self.unknownSystemIDs = unknownSystemIDs
        self.duplicateSystemIDs = duplicateSystemIDs
        self.mismatchedSystemIDs = mismatchedSystemIDs
    }
}

public struct MiniAppLiveActivityCleanupFailure: Error, Sendable {
    public let systemIDs: [String]
    public init(systemIDs: [String]) { self.systemIDs = systemIDs }
}

public enum MiniAppLiveActivityError: Error, Equatable, Sendable {
    case invalidIdentity, staleIdentity, missingRegistration, duplicateRegistration
    case nativeStateUnresolved(systemID: String)
}

public protocol MiniAppLiveActivityNativeDriver<StartInput, UpdateInput, EndInput>: Sendable {
    associatedtype StartInput: Sendable
    associatedtype UpdateInput: Sendable
    associatedtype EndInput: Sendable
    func request(identity: MiniAppContinuingIdentity, input: StartInput) async throws -> String
    func records() async -> [MiniAppLiveActivityNativeRecord]
    func update(systemID: String, input: UpdateInput) async
    func end(systemID: String, input: EndInput) async
    func awaitEnded(systemID: String) async -> Bool
    func changes() async -> AsyncStream<Void>
}

public struct MiniAppLiveActivityJournalAccess: Sendable {
    public let read: @Sendable () throws -> [MiniAppContinuingRegistration]
    public let update: @Sendable (@Sendable (inout [MiniAppContinuingRegistration]) throws -> Void) throws -> Void
    public init(read: @escaping @Sendable () throws -> [MiniAppContinuingRegistration],
                update: @escaping @Sendable (@Sendable (inout [MiniAppContinuingRegistration]) throws -> Void) throws -> Void) {
        self.read = read; self.update = update
    }
}

#if os(iOS) || os(macOS)
public extension MiniAppLiveActivityJournalAccess {
    init(_ journal: MiniAppContinuingJournal) {
        self.init(read: { try journal.read() }, update: { mutation in try journal.update(mutation) })
    }
}
#endif

private actor MiniAppLiveActivityObservation {
    private var task: Task<Void, Never>?
    func start(stream: AsyncStream<Void>, reconcile: @escaping @Sendable () async -> Void) {
        guard task == nil else { return }
        task = Task { for await _ in stream { if Task.isCancelled { break }; await reconcile() } }
    }
    func stop() { task?.cancel(); task = nil }
}

/// Share one value for one owner/native type in the app process. The operation
/// gate stays occupied across validation, Feature mutation, and native request.
public struct MiniAppLiveActivityCoordinator<Driver: MiniAppLiveActivityNativeDriver>: Sendable {
    public typealias Admission = @Sendable (MiniAppContinuingIdentity) async throws -> Void
    private let owner: MiniAppID
    private let gate: MiniAppContinuingOperationGate
    private let journal: MiniAppLiveActivityJournalAccess
    private let native: Driver
    private let admission: Admission
    private let observation = MiniAppLiveActivityObservation()

    public init(owner: MiniAppID, gate: MiniAppContinuingOperationGate,
                journal: MiniAppLiveActivityJournalAccess, native: Driver,
                admission: @escaping Admission) {
        precondition(owner.isValid)
        self.owner = owner; self.gate = gate; self.journal = journal
        self.native = native; self.admission = admission
    }

    public func start(identity proposed: MiniAppContinuingIdentity, input: Driver.StartInput) async throws
        -> MiniAppLiveActivityDescriptor {
        try await gate.perform { [self] in
            try await validate(proposed)
            let saved = try journal.read()
            let nativeRecords = await native.records()
            let os = nativeRecords.filter { $0.identity.owner == owner.rawValue }
            let sameBusiness: @Sendable (MiniAppContinuingIdentity) -> Bool = { identity in
                identity.owner == proposed.owner && identity.localID == proposed.localID
                    && identity.generation == proposed.generation
            }
            for row in saved.filter({ sameBusiness($0.identity) && $0.phase != .ending }) {
                if let systemID = row.systemID,
                   let nativeRow = os.first(where: { $0.systemID == systemID && $0.identity == row.identity }),
                   [.pending, .active, .stale].contains(nativeRow.state) {
                    return .init(identity: row.identity, systemID: systemID)
                }
            }
            if let orphan = os.first(where: { sameBusiness($0.identity) && [.pending, .active, .stale].contains($0.state) }) {
                try journal.update { rows in
                    rows.removeAll { sameBusiness($0.identity) }
                    rows.append(.init(identity: orphan.identity, systemID: orphan.systemID, phase: .active))
                }
                return .init(identity: orphan.identity, systemID: orphan.systemID)
            }
            try journal.update { rows in
                rows.removeAll { sameBusiness($0.identity) }
                rows.append(.init(identity: proposed, phase: .starting))
            }
            let systemID = try await native.request(identity: proposed, input: input)
            try journal.update { rows in
                guard let index = rows.firstIndex(where: { $0.identity == proposed }) else {
                    throw MiniAppLiveActivityError.missingRegistration
                }
                rows[index].systemID = systemID; rows[index].phase = .active
            }
            return .init(identity: proposed, systemID: systemID)
        }
    }

    /// Feature mutation runs only after complete admission/registration checks.
    /// If the native call doesn't reflect the request, the committed Feature
    /// mutation is an explicit non-atomic partial success and reconcile follows.
    @discardableResult
    public func update<Result: Sendable>(_ descriptor: MiniAppLiveActivityDescriptor,
        prepare: @escaping @Sendable () throws -> (Result, Driver.UpdateInput)) async throws -> Result {
        try await gate.perform { [self] in
            try await validate(descriptor.identity)
            try await requireActive(descriptor)
            let (result, input) = try prepare()
            await native.update(systemID: descriptor.systemID, input: input)
            return result
        }
    }

    public func end(_ descriptor: MiniAppLiveActivityDescriptor, input: Driver.EndInput) async throws {
        try await gate.perform { [self] in
            try await validate(descriptor.identity)
            try await requireActive(descriptor)
            try markEnding(descriptor)
            await native.end(systemID: descriptor.systemID, input: input)
            guard await native.awaitEnded(systemID: descriptor.systemID) else {
                throw MiniAppLiveActivityError.nativeStateUnresolved(systemID: descriptor.systemID)
            }
            try remove(descriptor.identity)
        }
    }

    @discardableResult
    public func reconcile() async throws -> MiniAppLiveActivityReconcileReport {
        try await gate.performMaintenance { [self] in try await reconcileInsideGate() }
    }

    public func close() async { await observation.stop(); await gate.close() }

    public func open() async {
        await gate.open()
        let stream = await native.changes()
        await observation.start(stream: stream) { [self] in _ = try? await reconcile() }
    }

    public func endOwned(input: @escaping @Sendable (MiniAppContinuingIdentity) -> Driver.EndInput) async throws {
        try await gate.performMaintenance { [self] in
            let nativeRecords = await native.records()
            let owned = nativeRecords.filter { $0.identity.owner == owner.rawValue }
            var failures: [String] = []
            for record in owned where record.state != .dismissed {
                do {
                    try markEndingIfSaved(record.identity, systemID: record.systemID)
                    await native.end(systemID: record.systemID, input: input(record.identity))
                    guard await native.awaitEnded(systemID: record.systemID) else {
                        throw MiniAppLiveActivityError.nativeStateUnresolved(systemID: record.systemID)
                    }
                    try remove(record.identity)
                } catch { failures.append(record.systemID) }
            }
            if !failures.isEmpty { throw MiniAppLiveActivityCleanupFailure(systemIDs: failures) }
            _ = try await reconcileInsideGate()
        }
    }

    public func surface(id: String,
        finalInput: @escaping @Sendable (MiniAppContinuingIdentity) -> Driver.EndInput) -> MiniAppContinuingSurface {
        MiniAppContinuingSurface(owner: owner, id: id, close: { await self.close() },
            reconcile: { _ = try await self.reconcile() },
            endOwned: { try await self.endOwned(input: finalInput) }, open: { await self.open() })
    }

    private func reconcileInsideGate() async throws -> MiniAppLiveActivityReconcileReport {
        let nativeRecords = await native.records()
        let os = nativeRecords.filter { $0.identity.owner == owner.rawValue }
        let saved = try journal.read()
        var report = MiniAppLiveActivityReconcileReport()
        var kept: [MiniAppContinuingRegistration] = []
        for var row in saved {
            let identityMatches = os.filter { $0.identity == row.identity }
            if identityMatches.count > 1 { report.duplicateSystemIDs += identityMatches.map(\.systemID) }
            if let systemID = row.systemID,
               let exact = identityMatches.first(where: { $0.systemID == systemID }) {
                if exact.state == .dismissed { continue }
                if exact.state == .ended { row.phase = .ending }
                // Never reopen .ending merely because OS still reports active.
                kept.append(row)
            } else if row.systemID == nil, identityMatches.count == 1,
                      let exact = identityMatches.first, exact.state != .dismissed {
                row.systemID = exact.systemID
                row.phase = exact.state == .ended ? .ending : .active
                kept.append(row)
            } else if row.systemID != nil, !identityMatches.isEmpty {
                report.mismatchedSystemIDs += identityMatches.map(\.systemID)
                kept.append(row)
            }
        }
        let known = Set(saved.compactMap(\.systemID))
        report.unknownSystemIDs = os.filter { !known.contains($0.systemID) }.map(\.systemID)
        try journal.update { $0 = kept }
        return report
    }

    private func validate(_ identity: MiniAppContinuingIdentity) async throws {
        guard identity.owner == owner.rawValue, !identity.localID.isEmpty else { throw MiniAppLiveActivityError.invalidIdentity }
        try await admission(identity)
    }

    private func requireActive(_ descriptor: MiniAppLiveActivityDescriptor) async throws {
        guard try journal.read().contains(where: {
            $0.identity == descriptor.identity && $0.systemID == descriptor.systemID && $0.phase == .active
        }) else { throw MiniAppLiveActivityError.staleIdentity }
        let nativeRecords = await native.records()
        guard nativeRecords.contains(where: {
            $0.identity == descriptor.identity && $0.systemID == descriptor.systemID
                && [.pending, .active, .stale].contains($0.state)
        }) else { throw MiniAppLiveActivityError.staleIdentity }
    }

    private func markEnding(_ descriptor: MiniAppLiveActivityDescriptor) throws {
        try journal.update { rows in
            guard let index = rows.firstIndex(where: {
                $0.identity == descriptor.identity && $0.systemID == descriptor.systemID && $0.phase == .active
            }) else { throw MiniAppLiveActivityError.staleIdentity }
            rows[index].phase = .ending
        }
    }
    private func markEndingIfSaved(_ identity: MiniAppContinuingIdentity, systemID: String) throws {
        try journal.update { rows in
            if let index = rows.firstIndex(where: { $0.identity == identity && ($0.systemID == nil || $0.systemID == systemID) }) {
                rows[index].systemID = systemID; rows[index].phase = .ending
            }
        }
    }
    private func remove(_ identity: MiniAppContinuingIdentity) throws {
        try journal.update { $0.removeAll { $0.identity == identity } }
    }
}
