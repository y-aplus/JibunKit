import Foundation

/// Native continuing work belongs to the Feature, not its current screen.
/// Closures operate on one owner's service and must be idempotent for retries.
public struct MiniAppContinuingSurface: Sendable {
    public let owner: MiniAppID
    public let id: String
    public let close: @Sendable () async throws -> Void
    public let reconcile: @Sendable () async throws -> Void
    public let endOwned: @Sendable () async throws -> Void
    public let open: @Sendable () async throws -> Void

    public init(owner: MiniAppID, id: String,
        close: @escaping @Sendable () async throws -> Void,
        reconcile: @escaping @Sendable () async throws -> Void,
        endOwned: @escaping @Sendable () async throws -> Void,
        open: @escaping @Sendable () async throws -> Void) {
        precondition(owner.isValid && MiniAppID(id).isValid)
        self.owner = owner
        self.id = id
        self.close = close
        self.reconcile = reconcile
        self.endOwned = endOwned
        self.open = open
    }
}

/// Composes several native surfaces of one Feature with its durable external
/// admission. Never serializes or closes a different Feature's service.
public struct MiniAppContinuingSurfaceGroup: Sendable {
    public let owner: MiniAppID
    public let surfaces: [MiniAppContinuingSurface]

    public struct Failure: LocalizedError, Sendable {
        public let stage: String
        public let reasons: [String]
        public var errorDescription: String? { "Continuing surfaces \(stage): " + reasons.joined(separator: "; ") }
    }

    public init(owner: MiniAppID, surfaces: [MiniAppContinuingSurface]) {
        precondition(owner.isValid && surfaces.allSatisfy { $0.owner == owner })
        precondition(Set(surfaces.map(\.id)).count == surfaces.count)
        self.owner = owner
        self.surfaces = surfaces
    }

    public func close() async throws { try await each("close") { try await $0.close() } }
    public func reconcile() async throws { try await each("reconcile") { try await $0.reconcile() } }
    public func endOwned() async throws { try await each("end") { try await $0.endOwned() } }

    private func open() async throws {
        // Do not open a partially reconciled group.
        try await reconcile()
        do { try await each("open") { try await $0.open() } }
        catch {
            let original = error.localizedDescription
            do { try await close() }
            catch { throw Failure(stage: "open rollback", reasons: [original, error.localizedDescription]) }
            throw Failure(stage: "open", reasons: [original])
        }
    }

    private func each(_ stage: String,
        _ operation: @Sendable (MiniAppContinuingSurface) async throws -> Void) async throws {
        var reasons: [String] = []
        // Even if one surface fails, close/cleanup the owner's other surfaces.
        for surface in surfaces {
            do { try await operation(surface) }
            catch { reasons.append("\(surface.id): \(error.localizedDescription)") }
        }
        if !reasons.isEmpty { throw Failure(stage: stage, reasons: reasons) }
    }

    public func wrapping(_ external: MiniAppExternalAccess) -> MiniAppExternalAccess {
        precondition(external.id == owner)
        return MiniAppExternalAccess(id: owner, prepare: external.prepare, close: {
            var reasons: [String] = []
            do { try await close() } catch { reasons.append(error.localizedDescription) }
            // Persist rejection even when a native adapter cannot close cleanly.
            do { try await external.close() } catch { reasons.append(error.localizedDescription) }
            if !reasons.isEmpty { throw Failure(stage: "admission", reasons: reasons) }
        }, open: {
            try await external.open()
            do { try await open() }
            catch {
                let original = error.localizedDescription
                do { try await external.close() }
                catch { throw Failure(stage: "enable rollback", reasons: [original, error.localizedDescription]) }
                throw Failure(stage: "enable", reasons: [original])
            }
        }, restoreLifecycle: { inner in
            let session = ContinuingRestoreSession(group: self, inner: external.restoreLifecycle(inner))
            return MiniAppRestoreLifecycle(stop: { try await session.stop() },
                resume: { try await session.resume() },
                recoverAfterFailedStop: { try await session.recover() })
        })
    }

    private actor ContinuingRestoreSession {
        let group: MiniAppContinuingSurfaceGroup
        let inner: MiniAppRestoreLifecycle
        var started = false
        var innerAttempted = false

        init(group: MiniAppContinuingSurfaceGroup, inner: MiniAppRestoreLifecycle) {
            self.group = group
            self.inner = inner
        }

        func stop() async throws {
            guard !started else { throw MiniAppContinuingError.admissionClosed }
            started = true
            try await group.close()
            innerAttempted = true
            try await inner.stop()
            try await group.endOwned()
        }

        func resume() async throws {
            guard started, innerAttempted else { throw MiniAppContinuingError.admissionClosed }
            try await inner.resume()
            // The durable admission may still be disabled independently by
            // management. Feature actions always check that durable state too.
            try await group.open()
            started = false
            innerAttempted = false
        }

        func recover() async throws {
            guard started else { return }
            if innerAttempted { try await inner.recoverAfterFailedStop?() }
            try await group.open()
            started = false
            innerAttempted = false
        }
    }
}
