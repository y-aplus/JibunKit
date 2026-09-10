import Foundation

/// One completion boundary per owned native URLSession. Forward the session's
/// didBecomeInvalidWithError delegate callback to didBecomeInvalid(_:error:).
/// Does not replace task/data/download/authentication delegate behavior.
public actor MiniAppURLSessionLifetime {
    public enum Failure: Error, Equatable { case sharedSession, differentSession }
    private var session: URLSession?
    private var finishing = false
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    public init() {}

    /// Closes native task admission and lets existing requests finish. Cancel
    /// and join owned Swift tasks beforehand when shutdown should cancel work.
    /// Concurrent callers join; cancelling a waiter does not claim early cleanup.
    /// Requires delegate forwarding. Never call from a callback this waits for.
    /// Do not externally call invalidateAndCancel: its invalidation callback is
    /// not the graceful task/delegate completion boundary used by this method.
    public func finishAndWait(_ session: URLSession) async throws {
        guard session !== URLSession.shared else { throw Failure.sharedSession }
        try bind(session)
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
            if !finishing {
                finishing = true
                session.finishTasksAndInvalidate()
            }
        }
    }

    /// Forward after any delegate-owned cleanup which must precede persistence.
    /// A different session or duplicate callback cannot complete this lifetime.
    @discardableResult
    public func didBecomeInvalid(_ session: URLSession, error: Error?) -> Bool {
        guard session !== URLSession.shared else { return false }
        do { try bind(session) } catch { return false }
        guard result == nil else { return false }
        let result: Result<Void, Error> = error.map { .failure($0) } ?? .success(())
        self.result = result
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume(with: result) }
        return true
    }

    private func bind(_ session: URLSession) throws {
        if let owned = self.session {
            guard owned === session else { throw Failure.differentSession }
        } else { self.session = session }
    }
}
