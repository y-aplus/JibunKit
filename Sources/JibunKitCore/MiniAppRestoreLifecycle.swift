import Foundation

/// Feature-owned coordination for restoring live data. Stop must close admission
/// and await users of the store. If stop throws, it must leave a usable runtime
/// itself or provide recoverAfterFailedStop for partially stopped resources.
public struct MiniAppRestoreLifecycle: Sendable {
    public let stop: @Sendable () async throws -> Void
    public let resume: @Sendable () async throws -> Void
    public let recoverAfterFailedStop: (@Sendable () async throws -> Void)?

    public init(stop: @escaping @Sendable () async throws -> Void,
                resume: @escaping @Sendable () async throws -> Void,
                recoverAfterFailedStop: (@Sendable () async throws -> Void)? = nil) {
        self.stop = stop
        self.resume = resume
        self.recoverAfterFailedStop = recoverAfterFailedStop
    }

    public struct Failure: LocalizedError, Sendable {
        public let restoreReason: String?
        public let resumeReason: String
        public var errorDescription: String? {
            if let restoreReason { return "Restore failed: \(restoreReason); runtime resume failed: \(resumeReason)" }
            return "Data restored, but runtime resume failed: \(resumeReason)"
        }
    }

    struct StopFailure: LocalizedError {
        let reason: String
        let recoveryReason: String?
        var errorDescription: String? {
            guard let recoveryReason else { return reason }
            return "Stop failed: \(reason); recovery after failed stop failed: \(recoveryReason)"
        }
    }

    func perform(_ apply: @Sendable () async throws -> Void) async throws {
        do { try await stop() } catch {
            let stopReason = error.localizedDescription
            do { try await recoverAfterFailedStop?() } catch {
                throw StopFailure(reason: stopReason, recoveryReason: error.localizedDescription)
            }
            throw StopFailure(reason: stopReason, recoveryReason: nil)
        }
        var restoreError: (any Error)?
        do { try await apply() } catch { restoreError = error }
        do { try await resume() } catch {
            throw Failure(restoreReason: restoreError?.localizedDescription, resumeReason: error.localizedDescription)
        }
        if let restoreError { throw restoreError }
    }
}
