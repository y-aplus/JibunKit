import Foundation

public enum MiniAppAlarmState: String, Codable, Equatable, Sendable {
    case scheduled, countdown, paused, alerting, unknown
}

public enum MiniAppAlarmAction: String, Codable, Equatable, Sendable {
    case stop, cancel, countdown, pause, resume
}

public enum MiniAppAlarmAuthorizationState: String, Codable, Equatable, Sendable {
    case notDetermined, denied, authorized
}

/// Authorization is app-scoped. Do not use this value as Feature admission.
public protocol MiniAppAlarmAuthorizationClient: Sendable {
    func state() async -> MiniAppAlarmAuthorizationState
    func request() async throws -> MiniAppAlarmAuthorizationState
}

public enum MiniAppAlarmError: Error, Equatable, Sendable {
    case wrongOwner
    case staleGeneration
    case staleRegistration
    case missingRegistration
    case invalidNativeState(action: MiniAppAlarmAction, observed: MiniAppAlarmState?)
    case nativeDidNotConverge(action: MiniAppAlarmAction, systemID: UUID)
    case partialReplacement(newSystemID: UUID, oldSystemID: UUID, stage: String, reason: String)
}

public struct MiniAppAlarmSnapshot: Equatable, Sendable {
    public let id: UUID
    public let state: MiniAppAlarmState

    public init(id: UUID, state: MiniAppAlarmState) {
        self.id = id
        self.state = state
    }
}

public struct MiniAppAlarmRegistrationDescriptor: Equatable, Sendable {
    public let identity: MiniAppContinuingIdentity
    public let systemID: UUID
    public let phase: MiniAppContinuingRegistration.Phase

    public init(identity: MiniAppContinuingIdentity, systemID: UUID,
                phase: MiniAppContinuingRegistration.Phase) {
        self.identity = identity
        self.systemID = systemID
        self.phase = phase
    }
}

public protocol MiniAppAlarmNative: Sendable {
    associatedtype Configuration: Sendable
    func schedule(id: UUID, configuration: Configuration) async throws
    func perform(_ action: MiniAppAlarmAction, id: UUID) async throws
    func snapshots() async throws -> [MiniAppAlarmSnapshot]
    func updates() -> AsyncStream<Void>
}

public extension MiniAppAlarmNative {
    func updates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

public protocol MiniAppAlarmRegistrationStore: Sendable {
    func read() throws -> [MiniAppContinuingRegistration]
    func write(_ registrations: [MiniAppContinuingRegistration]) throws
}

public struct MiniAppAlarmReconciliation: Equatable, Sendable {
    public let active: [MiniAppContinuingIdentity]
    public let missing: [MiniAppContinuingIdentity]
    public let unknownSystemIDs: [UUID]
    public let recoveredStarting: [MiniAppContinuingIdentity]
    public let completedEnding: [MiniAppContinuingIdentity]
    public let duplicates: [MiniAppContinuingIdentity]

    public init(active: [MiniAppContinuingIdentity], missing: [MiniAppContinuingIdentity],
                unknownSystemIDs: [UUID], recoveredStarting: [MiniAppContinuingIdentity],
                completedEnding: [MiniAppContinuingIdentity], duplicates: [MiniAppContinuingIdentity] = []) {
        self.active = active
        self.missing = missing
        self.unknownSystemIDs = unknownSystemIDs
        self.recoveredStarting = recoveredStarting
        self.completedEnding = completedEnding
        self.duplicates = duplicates
    }
}

/// Typed, owner-scoped alarm lifecycle. Keep one instance for each Feature in the
/// app process and share it with that Feature's intents. `Configuration` remains
/// the Feature's concrete AlarmKit configuration; Core never erases metadata.
public final class MiniAppAlarmCoordinator<Native: MiniAppAlarmNative>: Sendable {
    public typealias Admission = @Sendable (_ localID: String, _ generation: UUID) async throws -> Void

    public let owner: MiniAppID
    private let native: Native
    private let store: any MiniAppAlarmRegistrationStore
    private let gate: MiniAppContinuingOperationGate
    private let admission: Admission
    private let confirmationAttempts: Int
    private let confirmationDelayNanoseconds: UInt64
    private let observer = MiniAppAlarmObserver()

    public init(owner: MiniAppID, native: Native, store: any MiniAppAlarmRegistrationStore,
                gate: MiniAppContinuingOperationGate = .init(),
                confirmationAttempts: Int = 8,
                confirmationDelayNanoseconds: UInt64 = 50_000_000,
                admission: @escaping Admission) {
        precondition(owner.isValid && confirmationAttempts > 0)
        self.owner = owner
        self.native = native
        self.store = store
        self.gate = gate
        self.confirmationAttempts = confirmationAttempts
        self.confirmationDelayNanoseconds = confirmationDelayNanoseconds
        self.admission = admission
    }

    public func schedule(localID: String, generation: UUID,
                         configuration: @Sendable (MiniAppContinuingIdentity, UUID) throws -> Native.Configuration)
        async throws -> MiniAppContinuingIdentity {
        try await gate.perform { [self] in
            try await admission(localID, generation)
            let identity = try MiniAppContinuingIdentity(owner: owner, localID: localID, generation: generation)
            let systemID = UUID()
            var records = try store.read()
            guard !records.contains(where: {
                $0.identity.localID == localID && $0.identity.generation == generation && $0.phase != .ending
            })
            else { throw MiniAppAlarmError.staleRegistration }
            records.append(.init(identity: identity, systemID: systemID.uuidString, phase: .starting))
            try store.write(records)
            try await native.schedule(id: systemID, configuration: try configuration(identity, systemID))
            try update(identity: identity, systemID: systemID, phase: .active)
            return identity
        }
    }

    /// Explicitly retries a persisted pre-native/ambiguous start with the same
    /// identity and system ID. It never manufactures a second registration.
    public func retryPending(_ identity: MiniAppContinuingIdentity,
                             configuration: @Sendable (MiniAppContinuingIdentity, UUID) throws -> Native.Configuration)
        async throws {
        try await gate.perform { [self] in
            try await admission(identity.localID, identity.generation)
            let record = try exactRecord(identity, phase: .starting)
            let id = try systemID(record)
            if try await native.snapshots().contains(where: { $0.id == id }) {
                try update(identity: identity, systemID: id, phase: .active)
                return
            }
            try await native.schedule(id: id, configuration: try configuration(identity, id))
            try update(identity: identity, systemID: id, phase: .active)
        }
    }

    public func current(localID: String, generation: UUID) throws -> MiniAppAlarmRegistrationDescriptor? {
        let candidates = try store.read().filter {
            $0.identity.localID == localID && $0.identity.generation == generation && $0.phase == .active
        }
        guard let record = candidates.last else { return nil }
        return .init(identity: record.identity, systemID: try systemID(record), phase: record.phase)
    }

    public func retryEnding(_ identity: MiniAppContinuingIdentity) async throws {
        try await gate.performMaintenance { [self] in
            let record = try exactRecord(identity, phase: .ending)
            let id = try systemID(record)
            let exists = try await native.snapshots().contains { $0.id == id }
            if exists {
                try await native.perform(.cancel, id: id)
                try await confirm(.cancel, id: id)
            }
            try remove(identity)
        }
    }

    /// Non-atomic replacement: the new alarm is made durable first. If removing
    /// the old alarm fails, both records remain so cold reconciliation can retry.
    public func replace(_ old: MiniAppContinuingIdentity,
                        configuration: @Sendable (MiniAppContinuingIdentity, UUID) throws -> Native.Configuration)
        async throws -> MiniAppContinuingIdentity {
        try await gate.perform { [self] in
            try checkOwner(old)
            try await admission(old.localID, old.generation)
            let oldRecord = try exactRecord(old, phase: .active)
            let oldID = try systemID(oldRecord)
            let next = try MiniAppContinuingIdentity(owner: owner, localID: old.localID,
                                                     generation: old.generation)
            let nextID = UUID()
            var records = try store.read()
            records.append(.init(identity: next, systemID: nextID.uuidString, phase: .starting))
            try store.write(records)
            try await native.schedule(id: nextID, configuration: try configuration(next, nextID))
            do {
                try update(identity: next, systemID: nextID, phase: .active)
                try update(identity: old, systemID: oldID, phase: .ending)
                try await native.perform(.cancel, id: oldID)
                try await confirm(.cancel, id: oldID)
                try remove(old)
                return next
            } catch {
                throw MiniAppAlarmError.partialReplacement(newSystemID: nextID, oldSystemID: oldID,
                    stage: replacementStage(old: old, next: next), reason: String(describing: error))
            }
        }
    }

    public func perform(_ action: MiniAppAlarmAction, identity: MiniAppContinuingIdentity) async throws {
        try await gate.perform { [self] in
            try checkOwner(identity)
            try await admission(identity.localID, identity.generation)
            let record = try exactRecord(identity, phase: .active)
            let id = try systemID(record)
            let observed = try await native.snapshots().first { $0.id == id }?.state
            try validate(action: action, observed: observed)
            if action == .cancel { try update(identity: identity, systemID: id, phase: .ending) }
            try await native.perform(action, id: id)
            try await confirm(action, id: id, initial: observed)
            if action == .cancel { try remove(identity) }
        }
    }

    /// The system already performs the standard stop/countdown button behavior.
    /// This validates an additional LiveActivityIntent callback without issuing
    /// a duplicate native stop and only then runs the Feature-owned event.
    public func handleSystemIntent(identity: MiniAppContinuingIdentity, systemID: UUID,
                                   event: @Sendable () async throws -> Void) async throws {
        try await gate.perform { [self] in
            try checkOwner(identity)
            try await admission(identity.localID, identity.generation)
            let record = try intentRecord(identity)
            guard try self.systemID(record) == systemID else { throw MiniAppAlarmError.staleRegistration }
            let systemStillExists = try await native.snapshots().contains { $0.id == systemID }
            if record.phase == .ending {
                guard !systemStillExists else { throw MiniAppAlarmError.staleRegistration }
            }
            try await event()
            if !systemStillExists { try remove(identity) }
        }
    }

    public func close() async {
        await observer.stop()
        await gate.close()
    }
    public func open() async {
        await gate.open()
        await startObserving()
    }

    public func reconcile() async throws -> MiniAppAlarmReconciliation {
        let result = try await gate.performMaintenance { [self] in try await reconcileInsideGate() }
        await startObserving()
        return result
    }

    public func endOwned() async throws {
        try await gate.performMaintenance { [self] in
            let records = try store.read()
            var firstFailure: Error?
            for record in records {
                do {
                    let id = try systemID(record)
                    try update(identity: record.identity, systemID: id, phase: .ending)
                    let systemStillExists = try await native.snapshots().contains { $0.id == id }
                    if !systemStillExists {
                        try remove(record.identity)
                        continue
                    }
                    try await native.perform(.cancel, id: id)
                    try await confirm(.cancel, id: id)
                    try remove(record.identity)
                } catch {
                    if firstFailure == nil { firstFailure = error }
                    // Retain the ending record and continue this owner's cleanup.
                }
            }
            _ = try await reconcileInsideGate()
            if let firstFailure { throw firstFailure }
        }
    }

    public func surface(id: String = "alarmkit") -> MiniAppContinuingSurface {
        MiniAppContinuingSurface(owner: owner, id: id,
            close: { [self] in await close() },
            reconcile: { [self] in _ = try await reconcile() },
            endOwned: { [self] in try await endOwned() },
            open: { [self] in await open() })
    }

    private func reconcileInsideGate() async throws -> MiniAppAlarmReconciliation {
        let snapshots = try await native.snapshots()
        let nativeIDs = Set(snapshots.map(\.id))
        var records = try store.read()
        let knownIDs = Set(records.compactMap { $0.systemID.flatMap(UUID.init(uuidString:)) })
        var active: [MiniAppContinuingIdentity] = []
        var missing: [MiniAppContinuingIdentity] = []
        var recovered: [MiniAppContinuingIdentity] = []
        var completed: [MiniAppContinuingIdentity] = []
        var duplicates: [MiniAppContinuingIdentity] = []
        records.removeAll { record in
            guard let text = record.systemID, let id = UUID(uuidString: text) else {
                missing.append(record.identity); return false
            }
            switch (record.phase, nativeIDs.contains(id)) {
            case (.starting, true): recovered.append(record.identity); active.append(record.identity); return false
            case (.ending, false): completed.append(record.identity); return true
            case (.active, true), (.ending, true): active.append(record.identity); return false
            case (.starting, false): missing.append(record.identity); return false
            // Preserve one callback/reconcile window after a standard stop.
            // A second reconciliation sees ending+absent and removes it.
            case (.active, false): missing.append(record.identity); return false
            }
        }
        for index in records.indices where records[index].phase == .starting {
            if let text = records[index].systemID, let id = UUID(uuidString: text), nativeIDs.contains(id) {
                records[index].phase = .active
            }
        }
        for index in records.indices where records[index].phase == .active {
            if let text = records[index].systemID, let id = UUID(uuidString: text), !nativeIDs.contains(id) {
                records[index].phase = .ending
            }
        }
        var activeByBusinessID: [String: [Int]] = [:]
        for index in records.indices where records[index].phase == .active {
            let identity = records[index].identity
            activeByBusinessID[identity.localID + "\u{0}" + identity.generation.uuidString, default: []].append(index)
        }
        for indices in activeByBusinessID.values where indices.count > 1 {
            for index in indices.dropLast() {
                records[index].phase = .ending
                duplicates.append(records[index].identity)
            }
        }
        active = records.compactMap { record in
            guard record.phase == .active, let text = record.systemID, let id = UUID(uuidString: text),
                  nativeIDs.contains(id) else { return nil }
            return record.identity
        }
        try store.write(records)
        return .init(active: active, missing: missing,
                     unknownSystemIDs: Array(nativeIDs.subtracting(knownIDs)).sorted { $0.uuidString < $1.uuidString },
                     recoveredStarting: recovered, completedEnding: completed, duplicates: duplicates)
    }

    private func confirm(_ action: MiniAppAlarmAction, id: UUID,
                         initial: MiniAppAlarmState? = nil) async throws {
        for attempt in 0..<confirmationAttempts {
            let snapshot = try await native.snapshots().first { $0.id == id }
            let converged: Bool
            switch action {
            case .cancel: converged = snapshot == nil
            // A stopped one-shot may disappear; a recurring alarm may return to
            // its scheduled state. Either is an observed transition out of alert.
            case .stop:
                converged = snapshot == nil || (initial != .scheduled && snapshot?.state == .scheduled)
            case .pause: converged = snapshot?.state == .paused
            case .resume, .countdown: converged = snapshot?.state == .countdown
            }
            if converged { return }
            if attempt + 1 < confirmationAttempts && confirmationDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: confirmationDelayNanoseconds)
            } else { await Task.yield() }
        }
        throw MiniAppAlarmError.nativeDidNotConverge(action: action, systemID: id)
    }

    private func validate(action: MiniAppAlarmAction, observed: MiniAppAlarmState?) throws {
        let allowed: Bool = switch action {
        case .cancel: observed != nil
        case .stop: observed != nil
        case .countdown: observed == .alerting
        case .pause: observed == .countdown
        case .resume: observed == .paused
        }
        guard allowed else { throw MiniAppAlarmError.invalidNativeState(action: action, observed: observed) }
    }

    private func checkOwner(_ identity: MiniAppContinuingIdentity) throws {
        guard identity.owner == owner.rawValue else { throw MiniAppAlarmError.wrongOwner }
    }

    private func exactRecord(_ identity: MiniAppContinuingIdentity,
                             phase: MiniAppContinuingRegistration.Phase? = nil) throws
        -> MiniAppContinuingRegistration {
        try checkOwner(identity)
        let sameLocal = try store.read().filter { $0.identity.localID == identity.localID }
        guard sameLocal.contains(where: { $0.identity.generation == identity.generation })
        else { throw MiniAppAlarmError.staleGeneration }
        guard let record = sameLocal.first(where: { $0.identity == identity })
        else { throw MiniAppAlarmError.staleRegistration }
        if let phase, record.phase != phase { throw MiniAppAlarmError.staleRegistration }
        return record
    }

    private func intentRecord(_ identity: MiniAppContinuingIdentity) throws -> MiniAppContinuingRegistration {
        let record = try exactRecord(identity)
        if record.phase == .active { return record }
        guard record.phase == .ending else { throw MiniAppAlarmError.staleRegistration }
        let siblingIsCurrent = try store.read().contains {
            $0.identity != identity && $0.identity.localID == identity.localID
                && $0.identity.generation == identity.generation && $0.phase != .ending
        }
        guard !siblingIsCurrent else { throw MiniAppAlarmError.staleRegistration }
        return record
    }

    private func replacementStage(old: MiniAppContinuingIdentity,
                                  next: MiniAppContinuingIdentity) -> String {
        guard let records = try? store.read() else { return "journal-read" }
        let newPhase = records.first { $0.identity == next }?.phase.rawValue ?? "missing-new"
        let oldPhase = records.first { $0.identity == old }?.phase.rawValue ?? "missing-old"
        return "new-\(newPhase)-old-\(oldPhase)"
    }

    private func startObserving() async {
        let stream = native.updates()
        await observer.start(stream: stream) { [weak self] in
            guard let self else { return }
            _ = try? await self.gate.performMaintenance { [self] in try await reconcileInsideGate() }
        }
    }

    private func systemID(_ record: MiniAppContinuingRegistration) throws -> UUID {
        guard let text = record.systemID, let id = UUID(uuidString: text) else {
            throw MiniAppAlarmError.missingRegistration
        }
        return id
    }

    private func update(identity: MiniAppContinuingIdentity, systemID: UUID,
                        phase: MiniAppContinuingRegistration.Phase) throws {
        var records = try store.read()
        guard let index = records.firstIndex(where: { $0.identity == identity })
        else { throw MiniAppAlarmError.missingRegistration }
        records[index].systemID = systemID.uuidString
        records[index].phase = phase
        try store.write(records)
    }

    private func remove(_ identity: MiniAppContinuingIdentity) throws {
        var records = try store.read()
        records.removeAll { $0.identity == identity }
        try store.write(records)
    }
}

private actor MiniAppAlarmObserver {
    private var task: Task<Void, Never>?

    func start(stream: AsyncStream<Void>, onUpdate: @escaping @Sendable () async -> Void) {
        guard task == nil else { return }
        task = Task {
            for await _ in stream {
                guard !Task.isCancelled else { break }
                await onUpdate()
            }
            task = nil
        }
    }

    func stop() async {
        let running = task
        task = nil
        running?.cancel()
        _ = await running?.result
    }
}
