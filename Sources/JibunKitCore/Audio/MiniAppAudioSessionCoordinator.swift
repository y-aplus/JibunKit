import Foundation

@MainActor
public final class MiniAppAudioSessionCoordinator {
    private enum StopContext { @TaskLocal static var token: UUID? }
    public struct Lease: Hashable, Sendable {
        public let owner: MiniAppID
        public let generation: UInt64
        fileprivate let token: UUID
    }

    public struct Conflict: Sendable {
        public let requester: MiniAppID
        public let incumbentOwners: Set<MiniAppID>
        public let requestedProfiles: [MiniAppAudioProfile]
        public let reason: String
        fileprivate let revision: UInt64
        fileprivate let request: MiniAppAudioRequest
        fileprivate let stop: Stop
        fileprivate let receive: Receive
    }

    public enum Admission: Sendable {
        case acquired(Lease)
        case conflict(Conflict)
    }

    public enum ConflictResolution: Sendable {
        case keepCurrent
        case replaceOwners(Set<MiniAppID>)
    }

    public struct PartialStop: Sendable, Equatable {
        public let stoppedOwners: Set<MiniAppID>
        public let remainingOwners: Set<MiniAppID>
        public let reason: String
    }

    public enum SessionState: Sendable, Equatable {
        case inactive
        case active(MiniAppAudioProfile)
        case interrupted(MiniAppAudioProfile)
        case resetRequired(MiniAppAudioProfile)
        case deactivationFailed(MiniAppAudioProfile, String)
        case recoveryFailed(MiniAppAudioProfile, String)
    }

    public enum Failure: Error, Sendable, Equatable {
        case invalidRequest
        case ownerAlreadyActive
        case conflictDeclined
        case staleConflict
        case incompatibleSelection
        case coordinatorBusy
        case unknownLease
        case stopReentry
        case producerStop(String)
        case driver(String)
        case driverChangeFailed(change: String, recovery: String?)
        case sessionRecoveryRequired
        case resumeNotAllowed
        case partialStop(PartialStop)
    }

    public typealias Stop = @MainActor @Sendable () async throws -> Void
    public typealias Receive = @MainActor @Sendable (MiniAppAudioEvent) -> Void

    private struct Entry {
        let lease: Lease
        let request: MiniAppAudioRequest
        let stop: Stop
        let receive: Receive
        var intent: MiniAppAudioIntent = .paused
        var interruptedGeneration: UInt64?
        var interruptionEndedGeneration: UInt64?
        var producerStopped = false
    }

    private let driver: any MiniAppAudioSessionDriver
    private var entries: [UUID: Entry] = [:]
    private var currentProfile: MiniAppAudioProfile?
    private var generations: [MiniAppID: UInt64] = [:]
    private var revision: UInt64 = 0
    private var transactionInProgress = false
    private var stoppingTokens: Set<UUID> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var sessionState: SessionState = .inactive

    public init(driver: any MiniAppAudioSessionDriver) { self.driver = driver }

    public var activeOwners: Set<MiniAppID> { Set(entries.values.map(\.lease.owner)) }
    public var stoppedOwners: Set<MiniAppID> { Set(entries.values.filter(\.producerStopped).map(\.lease.owner)) }
    public var activeProfile: MiniAppAudioProfile? { currentProfile }

    public func acquire(owner: MiniAppID, request: MiniAppAudioRequest,
                        stop: @escaping Stop, receive: @escaping Receive) async throws -> Admission {
        try Task.checkCancellation()
        await waitUntilIdle()
        switch sessionState {
        case .inactive, .active: break
        default: throw Failure.sessionRecoveryRequired
        }
        if case .recoveryFailed = sessionState { throw Failure.sessionRecoveryRequired }
        if case .deactivationFailed = sessionState { throw Failure.sessionRecoveryRequired }
        guard owner.isValid, !request.acceptableProfiles.isEmpty,
              Set(request.acceptableProfiles).count == request.acceptableProfiles.count
        else { throw Failure.invalidRequest }
        guard !entries.values.contains(where: { $0.lease.owner == owner }) else {
            throw Failure.ownerAlreadyActive
        }

        if entries.isEmpty {
            let lease = try install(owner: owner, request: request, stop: stop, receive: receive,
                                    profile: request.acceptableProfiles[0], activatesDriver: true)
            return .acquired(lease)
        }
        if let profile = commonProfile(adding: request) {
            if profile != currentProfile {
                try changeProfile(to: profile)
            }
            return .acquired(try install(owner: owner, request: request, stop: stop, receive: receive,
                                         profile: profile, activatesDriver: false))
        }
        return .conflict(Conflict(
            requester: owner, incumbentOwners: activeOwners,
            requestedProfiles: request.acceptableProfiles,
            reason: "No explicitly accepted AudioSession profile is shared by all owners.",
            revision: revision, request: request, stop: stop, receive: receive
        ))
    }

    public func resolve(_ conflict: Conflict, as decision: ConflictResolution) async throws -> Lease {
        try Task.checkCancellation()
        await waitUntilIdle()
        guard conflict.revision == revision,
              conflict.incumbentOwners == activeOwners,
              !entries.values.contains(where: { $0.lease.owner == conflict.requester })
        else { throw Failure.staleConflict }
        guard case .replaceOwners(let selected) = decision else { throw Failure.conflictDeclined }
        guard !selected.isEmpty, selected.isSubset(of: activeOwners) else { throw Failure.incompatibleSelection }
        let survivors = entries.values.filter { !selected.contains($0.lease.owner) }
        guard let profile = firstCommonProfile(requests: survivors.map(\.request) + [conflict.request]) else {
            throw Failure.incompatibleSelection
        }

        transactionInProgress = true
        defer { finishTransaction(); stoppingTokens.removeAll() }
        var stopped: Set<MiniAppID> = []
        for entry in entries.values.filter({ selected.contains($0.lease.owner) })
            .sorted(by: { $0.lease.owner.rawValue < $1.lease.owner.rawValue }) {
            stoppingTokens.insert(entry.lease.token)
            do { try await Task { @MainActor in
                try await StopContext.$token.withValue(entry.lease.token) { try await entry.stop() }
            }.value }
            catch {
                try failPartialStop(stopped: stopped, reason: String(describing: error))
            }
            entries[entry.lease.token] = nil
            stopped.insert(entry.lease.owner)
            revision &+= 1
            if Task.isCancelled {
                try failPartialStop(stopped: stopped, reason: "Conflict resolution was cancelled after a producer stopped.")
            }
        }
        do {
            try driver.apply(profile)
            if entries.isEmpty { try driver.setActive(true, notifyOthersOnDeactivation: false) }
            currentProfile = profile
            sessionState = .active(profile)
            return try install(owner: conflict.requester, request: conflict.request,
                               stop: conflict.stop, receive: conflict.receive,
                               profile: profile, activatesDriver: false)
        } catch {
            if let profile = currentProfile { sessionState = .recoveryFailed(profile, String(describing: error)) }
            throw Failure.partialStop(.init(stoppedOwners: stopped, remainingOwners: activeOwners,
                                            reason: "AudioSession reconfiguration failed: \(error)"))
        }
    }

    /// Stops this lease's producer and joins completion before removing it.
    /// A stop callback must never call release for the same lease.
    public func release(_ lease: Lease) async throws {
        if let stopping = StopContext.token {
            throw stopping == lease.token ? Failure.stopReentry : Failure.coordinatorBusy
        }
        if stoppingTokens.contains(lease.token) { throw Failure.stopReentry }
        await waitUntilIdle()
        guard var entry = entries[lease.token], entry.lease == lease else { throw Failure.unknownLease }
        transactionInProgress = true
        stoppingTokens.insert(lease.token)
        defer { finishTransaction(); stoppingTokens.remove(lease.token) }
        if !entry.producerStopped {
            do { try await Task { @MainActor in
                try await StopContext.$token.withValue(entry.lease.token) { try await entry.stop() }
            }.value }
            catch { throw Failure.producerStop(String(describing: error)) }
            entry.producerStopped = true
            entries[lease.token] = entry
        }
        if entries.count == 1 {
            do { try driver.setActive(false, notifyOthersOnDeactivation: true) }
            catch {
                if let profile = currentProfile { sessionState = .deactivationFailed(profile, String(describing: error)) }
                throw Failure.driver(String(describing: error))
            }
        }
        entries[lease.token] = nil
        revision &+= 1
        if entries.isEmpty { currentProfile = nil; sessionState = .inactive }
    }

    public func updateIntent(_ intent: MiniAppAudioIntent, for lease: Lease) throws {
        guard var entry = entries[lease.token], entry.lease == lease else { throw Failure.unknownLease }
        entry.intent = intent
        if intent != .active { entry.interruptedGeneration = nil }
        entries[lease.token] = entry
    }

    /// Reapplies and activates the current profile after a valid interruption end or media-services reset.
    /// User/route stop intents are never overridden.
    public func reactivate(_ lease: Lease) async throws {
        await waitUntilIdle()
        guard var entry = entries[lease.token], entry.lease == lease, !entry.producerStopped,
              entry.intent == .active, let profile = currentProfile else { throw Failure.resumeNotAllowed }
        let allowed: Bool
        switch sessionState {
        case .interrupted: allowed = entry.interruptionEndedGeneration == lease.generation
        case .resetRequired, .recoveryFailed: allowed = true
        case .active: allowed = entry.interruptionEndedGeneration == lease.generation
        default: allowed = false
        }
        guard allowed else { throw Failure.resumeNotAllowed }
        do { try driver.apply(profile); try driver.setActive(true, notifyOthersOnDeactivation: false) }
        catch { sessionState = .recoveryFailed(profile, String(describing: error)); throw Failure.driver(String(describing: error)) }
        entry.interruptedGeneration = nil
        entry.interruptionEndedGeneration = nil
        entries[lease.token] = entry
        sessionState = .active(profile)
    }

    /// Repairs an unknown native state. With no owners it deactivates; otherwise it restores the accepted profile.
    public func recoverSession() async throws {
        await waitUntilIdle()
        if case .interrupted = sessionState { throw Failure.resumeNotAllowed }
        if entries.isEmpty {
            do { try driver.setActive(false, notifyOthersOnDeactivation: true) }
            catch { throw Failure.driver(String(describing: error)) }
            currentProfile = nil; sessionState = .inactive
        } else if let profile = currentProfile {
            do { try driver.apply(profile); try driver.setActive(true, notifyOthersOnDeactivation: false) }
            catch { sessionState = .recoveryFailed(profile, String(describing: error)); throw Failure.driver(String(describing: error)) }
            sessionState = .active(profile)
        }
    }

    /// A new explicit Play/Record intent. Unlike interruption auto-resume eligibility, this may recover a paused route.
    public func activateForUserAction(_ lease: Lease) async throws {
        await waitUntilIdle()
        guard var entry = entries[lease.token], entry.lease == lease, !entry.producerStopped,
              let profile = currentProfile else { throw Failure.resumeNotAllowed }
        entry.intent = .active
        do { try driver.apply(profile); try driver.setActive(true, notifyOthersOnDeactivation: false) }
        catch { sessionState = .recoveryFailed(profile, String(describing: error)); throw Failure.driver(String(describing: error)) }
        entry.interruptedGeneration = nil; entry.interruptionEndedGeneration = nil
        entries[lease.token] = entry; sessionState = .active(profile)
    }

    public func receiveInterruptionBegan() {
        if let profile = currentProfile { sessionState = .interrupted(profile) }
        for token in Array(entries.keys) {
            guard var entry = entries[token] else { continue }
            entry.interruptedGeneration = entry.intent == .active && entry.request.allowsInterruptionResume
                ? entry.lease.generation : nil
            entry.interruptionEndedGeneration = nil
            entries[token] = entry
            entry.receive(.interruptionBegan)
        }
    }

    public func receiveInterruptionEnded(shouldResume: Bool) {
        for token in Array(entries.keys) {
            guard var entry = entries[token] else { continue }
            let candidate = shouldResume && entry.intent == .active
                && entry.interruptedGeneration == entry.lease.generation
            entry.interruptionEndedGeneration = candidate ? entry.lease.generation : nil
            if !candidate { entry.interruptedGeneration = nil }
            entries[token] = entry
            entry.receive(.interruptionEnded(resumeCandidate: candidate))
        }
    }

    public func receiveRouteChange(reason: UInt) {
        entries.values.forEach { $0.receive(.routeChanged(reason: reason)) }
    }

    public func receiveMediaServicesReset() {
        if let profile = currentProfile { sessionState = .resetRequired(profile) }
        revision &+= 1
        entries.values.forEach { $0.receive(.mediaServicesReset) }
    }

    private func install(owner: MiniAppID, request: MiniAppAudioRequest, stop: @escaping Stop,
                         receive: @escaping Receive, profile: MiniAppAudioProfile,
                         activatesDriver: Bool) throws -> Lease {
        if activatesDriver {
            do { try driver.apply(profile); try driver.setActive(true, notifyOthersOnDeactivation: false) }
            catch {
                currentProfile = profile
                sessionState = .recoveryFailed(profile, String(describing: error))
                throw Failure.driver(String(describing: error))
            }
            currentProfile = profile
            sessionState = .active(profile)
        }
        let generation = (generations[owner] ?? 0) &+ 1
        generations[owner] = generation
        let lease = Lease(owner: owner, generation: generation, token: UUID())
        entries[lease.token] = Entry(lease: lease, request: request, stop: stop, receive: receive)
        revision &+= 1
        return lease
    }

    private func commonProfile(adding request: MiniAppAudioRequest) -> MiniAppAudioProfile? {
        firstCommonProfile(requests: entries.values.map(\.request) + [request])
    }

    private func changeProfile(to profile: MiniAppAudioProfile) throws {
        let previous = currentProfile
        do { try driver.apply(profile); currentProfile = profile; sessionState = .active(profile) }
        catch {
            let change = String(describing: error)
            guard let previous else { throw Failure.driverChangeFailed(change: change, recovery: nil) }
            do {
                try driver.apply(previous); try driver.setActive(true, notifyOthersOnDeactivation: false)
                currentProfile = previous; sessionState = .active(previous)
                throw Failure.driverChangeFailed(change: change, recovery: nil)
            } catch let failure as Failure { throw failure }
            catch {
                let recovery = String(describing: error)
                sessionState = .recoveryFailed(previous, recovery)
                throw Failure.driverChangeFailed(change: change, recovery: recovery)
            }
        }
    }

    private func firstCommonProfile(requests: [MiniAppAudioRequest]) -> MiniAppAudioProfile? {
        guard let preferred = requests.last?.acceptableProfiles else { return nil }
        return preferred.first { candidate in requests.allSatisfy { $0.acceptableProfiles.contains(candidate) } }
    }

    private func failPartialStop(stopped: Set<MiniAppID>, reason: String) throws -> Never {
        throw Failure.partialStop(.init(stoppedOwners: stopped, remainingOwners: activeOwners, reason: reason))
    }

    private func waitUntilIdle() async {
        while transactionInProgress {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
    }

    private func finishTransaction() {
        transactionInProgress = false
        let waiters = idleWaiters; idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
