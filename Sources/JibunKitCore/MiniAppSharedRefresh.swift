import Foundation

/// Journal acceptance and OS acceptance are separate. Rejected native requests
/// remain durable and can be submitted again by calling `reconcile()`.
public enum MiniAppSharedRefreshSchedulingResult {
    case idle(unregisteredRequests: Int)
    case submitted(earliestBeginDate: Date?, unregisteredRequests: Int)
    case rejected(any Error, unregisteredRequests: Int)
}

public struct MiniAppSharedRefreshReceipt {
    public let generation: UUID
    public let scheduling: MiniAppSharedRefreshSchedulingResult
}

public struct MiniAppSharedRefreshRequest: Equatable, Sendable {
    public let ownerIdentifier: String
    public let identifier: String
    /// Stable across recovery/retry. Feature work must tolerate redelivery.
    public let generation: UUID
    public let earliestBeginDate: Date?
    public let isRecovery: Bool
}

public enum MiniAppSharedRefreshCompletion {
    case recorded
    /// Cleanup is finished, but its durable acknowledgement failed. The work
    /// may be redelivered; the native batch will report failure.
    case acknowledgementFailed(any Error)
    case alreadyCompleted
}

/// One logical job in a host-owned native batch. Expiration requests cleanup;
/// it does not complete this job or another Feature's job.
@MainActor
public final class MiniAppSharedRefreshExecution {
    public let request: MiniAppSharedRefreshRequest
    public private(set) var isExpired = false
    public private(set) var isCompleted = false
    public var onExpiration: (@MainActor () -> Void)? {
        didSet { deliverExpirationIfNeeded() }
    }

    private var deliveredExpiration = false
    private var completion: (@MainActor (Bool) -> MiniAppSharedRefreshCompletion)?

    fileprivate init(
        request: MiniAppSharedRefreshRequest,
        completion: @escaping @MainActor (Bool) -> MiniAppSharedRefreshCompletion
    ) {
        self.request = request
        self.completion = completion
    }

    /// Call after work or expiration cleanup finishes. An unsuccessful job is
    /// retained for retry with the same generation until explicitly cancelled.
    @discardableResult
    public func complete(success: Bool) -> MiniAppSharedRefreshCompletion {
        guard !isCompleted, let completion else { return .alreadyCompleted }
        isCompleted = true
        self.completion = nil
        onExpiration = nil
        return completion(success)
    }

    fileprivate func expire() {
        guard !isCompleted, !isExpired else { return }
        isExpired = true
        deliverExpirationIfNeeded()
    }

    private func deliverExpirationIfNeeded() {
        guard isExpired, !isCompleted, !deliveredExpiration, let onExpiration else { return }
        deliveredExpiration = true
        onExpiration()
    }
}

/// Shares one explicitly registered BGAppRefreshTask identifier among Features.
/// Keep one center and one dedicated journal per host; register Feature handlers
/// during host launch, then call `reconcile()`. This is not a multiprocess writer
/// or an interceptor for other uses of BGTaskScheduler.
@MainActor
public final class MiniAppSharedRefreshCenter {
    public enum Failure: Error, Equatable {
        case invalidIdentifier
        case invalidDate
        case handlerAlreadyRegistered
        case handlerNotRegistered
        case nativeRegistrationRejected
    }

    private struct Key: Hashable {
        let owner: String
        let identifier: String
    }

    private final class Batch {
        let native: any MiniAppBackgroundTaskNative
        var executions: [UUID: MiniAppSharedRefreshExecution] = [:]
        var successful = true
        var expired = false

        init(native: any MiniAppBackgroundTaskNative) { self.native = native }
    }

    public let nativeIdentifier: String
    /// Reports failures from native launches/completions that have no synchronous
    /// caller. Submit/cancel/reconcile also return their scheduling result.
    public var onError: (@MainActor (any Error) -> Void)?

    private let journal: any MiniAppSharedRefreshJournaling
    private let scheduler: any MiniAppBackgroundTaskScheduling
    private let now: @MainActor () -> Date
    private var records: [MiniAppSharedRefreshRecord]
    private var handlers: [Key: @MainActor (MiniAppSharedRefreshExecution) -> Void] = [:]
    private var batches: [UUID: Batch] = [:]

    init(
        identifier: String,
        journal: any MiniAppSharedRefreshJournaling,
        scheduler: any MiniAppBackgroundTaskScheduling,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws {
        guard !identifier.isEmpty else { throw Failure.invalidIdentifier }
        nativeIdentifier = identifier
        self.journal = journal
        self.scheduler = scheduler
        self.now = now
        let loaded = try journal.load()
        records = loaded.map { record in
            var recovered = record
            if recovered.phase == .running { recovered.phase = .recovery }
            return recovered
        }
        if records != loaded { try journal.save(records) }
        let accepted = scheduler.register(identifier: identifier, kind: .appRefresh) { [weak self] native in
            guard let self else {
                native.setTaskCompleted(success: false)
                return
            }
            launch(native)
        }
        guard accepted else { throw Failure.nativeRegistrationRejected }
    }

    public func refreshes(for context: MiniAppContext) -> MiniAppSharedRefresh {
        MiniAppSharedRefresh(owner: context.id.storageNamespace, center: self)
    }

    /// Only the host's shared identifier is submitted/cancelled. Unregistered
    /// owners remain in the journal, but do not cause repeated empty launches.
    @discardableResult
    public func reconcile() -> MiniAppSharedRefreshSchedulingResult {
        let pending = records.filter { $0.phase != .running }
        let eligible = pending.filter { handlers[key($0)] != nil }
        let unresolved = pending.count - eligible.count
        guard !eligible.isEmpty else {
            scheduler.cancel(identifier: nativeIdentifier)
            return .idle(unregisteredRequests: unresolved)
        }
        let date: Date? = eligible.contains { $0.earliestBeginDate == nil }
            ? nil : eligible.compactMap(\.earliestBeginDate).min()
        do {
            try scheduler.submit(
                .init(identifier: nativeIdentifier, earliestBeginDate: date), kind: .appRefresh
            )
            return .submitted(earliestBeginDate: date, unregisteredRequests: unresolved)
        } catch {
            return .rejected(error, unregisteredRequests: unresolved)
        }
    }

    fileprivate func register(
        owner: String, identifier: String,
        handler: @escaping @MainActor (MiniAppSharedRefreshExecution) -> Void
    ) throws {
        guard !identifier.isEmpty else { throw Failure.invalidIdentifier }
        let key = Key(owner: owner, identifier: identifier)
        guard handlers[key] == nil else { throw Failure.handlerAlreadyRegistered }
        handlers[key] = handler
    }

    fileprivate func unregister(owner: String, identifier: String) {
        handlers.removeValue(forKey: Key(owner: owner, identifier: identifier))
    }

    fileprivate func submit(owner: String, identifier: String, date: Date?) throws -> MiniAppSharedRefreshReceipt {
        guard !identifier.isEmpty else { throw Failure.invalidIdentifier }
        guard date?.timeIntervalSinceReferenceDate.isFinite != false else { throw Failure.invalidDate }
        guard handlers[Key(owner: owner, identifier: identifier)] != nil else { throw Failure.handlerNotRegistered }
        let generation = UUID()
        // Replacing a pending request never removes an older running/recovered
        // generation whose work might already have changed Feature data.
        var updated = records.filter {
            !($0.owner == owner && $0.identifier == identifier && $0.phase == .pending)
        }
        updated.append(.init(owner: owner, identifier: identifier, generation: generation,
                             earliestBeginDate: date, phase: .pending))
        try persist(updated)
        return .init(generation: generation, scheduling: reconcile())
    }

    fileprivate func cancel(owner: String, identifier: String?) throws -> MiniAppSharedRefreshSchedulingResult {
        let updated = records.filter {
            !($0.owner == owner && (identifier == nil || $0.identifier == identifier) && $0.phase != .running)
        }
        try persist(updated)
        return reconcile()
    }

    fileprivate func pending(owner: String) -> [MiniAppSharedRefreshRequest] {
        records.filter { $0.owner == owner && $0.phase != .running }.map(request)
    }

    private func key(_ record: MiniAppSharedRefreshRecord) -> Key {
        Key(owner: record.owner, identifier: record.identifier)
    }

    private func request(_ record: MiniAppSharedRefreshRecord) -> MiniAppSharedRefreshRequest {
        .init(ownerIdentifier: record.owner, identifier: record.identifier,
              generation: record.generation, earliestBeginDate: record.earliestBeginDate,
              isRecovery: record.phase == .recovery)
    }

    private func persist(_ updated: [MiniAppSharedRefreshRecord]) throws {
        try journal.save(updated)
        records = updated
    }

    private func launch(_ native: any MiniAppBackgroundTaskNative) {
        let date = now()
        // Snapshot both jobs and handlers before delivering any callback. A's
        // callback cannot remove B from the batch by unregistering its handler.
        let selected = records.compactMap { record -> (MiniAppSharedRefreshRecord, @MainActor (MiniAppSharedRefreshExecution) -> Void)? in
            guard record.phase != .running, record.earliestBeginDate.map({ $0 <= date }) ?? true,
                  let handler = handlers[key(record)] else { return nil }
            return (record, handler)
        }
        let generations = Set(selected.map { $0.0.generation })
        var started = records
        for index in started.indices where generations.contains(started[index].generation) {
            started[index].phase = .running
        }
        do { try persist(started) }
        catch {
            native.setTaskCompleted(success: false)
            onError?(error)
            return
        }
        guard !selected.isEmpty else {
            report(reconcile())
            native.setTaskCompleted(success: true)
            return
        }
        let id = UUID()
        let batch = Batch(native: native)
        for (record, _) in selected {
            // Retain the center through unfinished executions, even after a
            // handler unregisters or the OS clears its expiration callback.
            batch.executions[record.generation] = MiniAppSharedRefreshExecution(request: request(record)) { [self] success in
                finish(generation: record.generation, batchID: id, success: success)
            }
        }
        batches[id] = batch
        native.expirationHandler = { [weak self] in self?.expire(batchID: id) }
        for (record, handler) in selected {
            if let execution = batch.executions[record.generation] { handler(execution) }
        }
        report(reconcile())
    }

    private func expire(batchID: UUID) {
        guard let batch = batches[batchID], !batch.expired else { return }
        batch.expired = true
        batch.successful = false
        let executions = Array(batch.executions.values)
        for execution in executions { execution.expire() }
    }

    private func finish(generation: UUID, batchID: UUID, success: Bool) -> MiniAppSharedRefreshCompletion {
        guard let batch = batches[batchID] else { return .alreadyCompleted }
        var updated = records
        if success { updated.removeAll { $0.generation == generation } }
        else {
            for index in updated.indices where updated[index].generation == generation {
                updated[index].phase = .recovery
            }
        }
        var failure: (any Error)?
        do { try persist(updated) }
        catch {
            failure = error
            // The durable record is still running and will recover on restart.
            // Keep it retryable in this process too, without calling cleanup twice.
            for index in records.indices where records[index].generation == generation {
                records[index].phase = .recovery
            }
        }
        batch.successful = batch.successful && success && failure == nil
        batch.executions.removeValue(forKey: generation)
        if batch.executions.isEmpty {
            batches.removeValue(forKey: batchID)
            batch.native.expirationHandler = nil
            // Remove this batch before native completion can reenter and launch
            // another generation under the same native identifier.
            batch.native.setTaskCompleted(success: batch.successful)
        }
        report(reconcile())
        if let failure {
            onError?(failure)
            return .acknowledgementFailed(failure)
        }
        return .recorded
    }

    private func report(_ result: MiniAppSharedRefreshSchedulingResult) {
        if case let .rejected(error, _) = result { onError?(error) }
    }
}

/// A Feature can mutate only its own logical requests. Cancelling pending work
/// does not complete an execution already delivered to its handler.
@MainActor
public final class MiniAppSharedRefresh {
    public let ownerIdentifier: String
    private let center: MiniAppSharedRefreshCenter

    fileprivate init(owner: String, center: MiniAppSharedRefreshCenter) {
        ownerIdentifier = owner
        self.center = center
    }

    public func register(identifier: String, handler: @escaping @MainActor (MiniAppSharedRefreshExecution) -> Void) throws {
        try center.register(owner: ownerIdentifier, identifier: identifier, handler: handler)
    }

    /// Stops future delivery; pending requests and already launched work remain.
    /// Call the host's reconcile after changing the set of handlers.
    public func unregister(identifier: String) {
        center.unregister(owner: ownerIdentifier, identifier: identifier)
    }

    @discardableResult
    public func submit(identifier: String, earliestBeginDate: Date? = nil) throws -> MiniAppSharedRefreshReceipt {
        try center.submit(owner: ownerIdentifier, identifier: identifier, date: earliestBeginDate)
    }

    @discardableResult
    public func cancel(identifier: String) throws -> MiniAppSharedRefreshSchedulingResult {
        try center.cancel(owner: ownerIdentifier, identifier: identifier)
    }

    @discardableResult
    public func cancelAllPendingRequests() throws -> MiniAppSharedRefreshSchedulingResult {
        try center.cancel(owner: ownerIdentifier, identifier: nil)
    }

    public var pendingRequests: [MiniAppSharedRefreshRequest] { center.pending(owner: ownerIdentifier) }
}
