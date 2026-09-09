import Foundation

/// Feature-owned coordination for restoring live data. Stop must close admission
/// and await users of the store. If stop throws, it must leave a usable runtime.
public struct MiniAppRestoreLifecycle: Sendable {
    public let stop: @Sendable () async throws -> Void
    public let resume: @Sendable () async throws -> Void

    public init(stop: @escaping @Sendable () async throws -> Void,
                resume: @escaping @Sendable () async throws -> Void) {
        self.stop = stop
        self.resume = resume
    }

    public struct Failure: LocalizedError, Sendable {
        public let restoreReason: String?
        public let resumeReason: String
        public var errorDescription: String? {
            if let restoreReason { return "Restore failed: \(restoreReason); runtime resume failed: \(resumeReason)" }
            return "Data restored, but runtime resume failed: \(resumeReason)"
        }
    }

    func perform(_ apply: @Sendable () async throws -> Void) async throws {
        try await stop()
        var restoreError: (any Error)?
        do { try await apply() } catch { restoreError = error }
        do { try await resume() } catch {
            throw Failure(restoreReason: restoreError?.localizedDescription, resumeReason: error.localizedDescription)
        }
        if let restoreError { throw restoreError }
    }
}
