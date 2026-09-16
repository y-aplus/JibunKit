import Foundation

@MainActor
public final class MiniAppAudioSessionCoordinator {
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
    }

    private let driver: any MiniAppAudioSessionDriver
    private var entries: [UUID: Entry] = [:]
    private var currentProfile: MiniAppAudioProfile?
    private var generations: [MiniAppID: UInt64] = [:]
    private var revision: UInt64 = 0
    private var transactionInProgress = false
    private var stoppingTokens: Set<UUID> = []

    public init(driver: any MiniAppAudioSessionDriver) { self.driver = driver }

    public var activeOwners: Set<MiniAppID> { Set(entries.values.map(\.lease.owner)) }
    public var activeProfile: MiniAppAudioProfile? { currentProfile }

    public func acquire(owner: MiniAppID, request: MiniAppAudioRequest,
                        stop: @escaping Stop, receive: @escaping Receive) async throws -> Admission {
        try Task.checkCancellation()
        guard !transactionInProgress else { throw Failure.coordinatorBusy }
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
                do { try driver.apply(profile) }
                catch { throw Failure.driver(String(describing: error)) }
                currentProfile = profile
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
        guard !transactionInProgress else { throw Failure.coordinatorBusy }
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
        defer { transactionInProgress = false; stoppingTokens.removeAll() }
        var stopped: Set<MiniAppID> = []
        for entry in entries.values.filter({ selected.contains($0.lease.owner) })
            .sorted(by: { $0.lease.owner.rawValue < $1.lease.owner.rawValue }) {
            stoppingTokens.insert(entry.lease.token)
            do { try await Task { @MainActor in try await entry.stop() }.value }
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
            return try install(owner: conflict.requester, request: conflict.request,
                               stop: conflict.stop, receive: conflict.receive,
                               profile: profile, activatesDriver: false)
        } catch {
            if entries.isEmpty { currentProfile = nil }
            throw Failure.partialStop(.init(stoppedOwners: stopped, remainingOwners: activeOwners,
                                            reason: "AudioSession reconfiguration failed: \(error)"))
        }
    }

    /// Stops this lease's producer and joins completion before removing it.
    /// A stop callback must never call release for the same lease.
    public func release(_ lease: Lease) async throws {
        guard let entry = entries[lease.token], entry.lease == lease else { throw Failure.unknownLease }
        if stoppingTokens.contains(lease.token) { throw Failure.stopReentry }
        guard !transactionInProgress else { throw Failure.coordinatorBusy }
        transactionInProgress = true
        stoppingTokens.insert(lease.token)
        defer { transactionInProgress = false; stoppingTokens.remove(lease.token) }
        do { try await Task { @MainActor in try await entry.stop() }.value }
        catch { throw Failure.producerStop(String(describing: error)) }
        entries[lease.token] = nil
        revision &+= 1
        if entries.isEmpty {
            do { try driver.setActive(false, notifyOthersOnDeactivation: true) }
            catch { throw Failure.driver(String(describing: error)) }
            currentProfile = nil
        }
    }

    public func updateIntent(_ intent: MiniAppAudioIntent, for lease: Lease) throws {
        guard var entry = entries[lease.token], entry.lease == lease else { throw Failure.unknownLease }
        entry.intent = intent
        if intent != .active { entry.interruptedGeneration = nil }
        entries[lease.token] = entry
    }

    public func receiveInterruptionBegan() {
        for token in Array(entries.keys) {
            guard var entry = entries[token] else { continue }
            entry.interruptedGeneration = entry.intent == .active && entry.request.allowsInterruptionResume
                ? entry.lease.generation : nil
            entries[token] = entry
            entry.receive(.interruptionBegan)
        }
    }

    public func receiveInterruptionEnded(shouldResume: Bool) {
        for token in Array(entries.keys) {
            guard var entry = entries[token] else { continue }
            let candidate = shouldResume && entry.intent == .active
                && entry.interruptedGeneration == entry.lease.generation
            entry.interruptedGeneration = nil
            entries[token] = entry
            entry.receive(.interruptionEnded(resumeCandidate: candidate))
        }
    }

    public func receiveRouteChange(reason: UInt) {
        entries.values.forEach { $0.receive(.routeChanged(reason: reason)) }
    }

    public func receiveMediaServicesReset() {
        entries.values.forEach { $0.receive(.mediaServicesReset) }
    }

    private func install(owner: MiniAppID, request: MiniAppAudioRequest, stop: @escaping Stop,
                         receive: @escaping Receive, profile: MiniAppAudioProfile,
                         activatesDriver: Bool) throws -> Lease {
        if activatesDriver {
            do { try driver.apply(profile); try driver.setActive(true, notifyOthersOnDeactivation: false) }
            catch { currentProfile = nil; throw Failure.driver(String(describing: error)) }
            currentProfile = profile
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

    private func firstCommonProfile(requests: [MiniAppAudioRequest]) -> MiniAppAudioProfile? {
        guard let preferred = requests.last?.acceptableProfiles else { return nil }
        return preferred.first { candidate in requests.allSatisfy { $0.acceptableProfiles.contains(candidate) } }
    }

    private func failPartialStop(stopped: Set<MiniAppID>, reason: String) throws -> Never {
        throw Failure.partialStop(.init(stoppedOwners: stopped, remainingOwners: activeOwners, reason: reason))
    }
}
