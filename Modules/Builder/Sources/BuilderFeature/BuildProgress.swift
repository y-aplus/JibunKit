import Foundation

/// What Builder remembers between launches. The token is stored separately.
public struct BuilderState: Codable, Equatable, Sendable {
    public var repository: BuildRepository?
    /// The last build this app requested, kept until another one starts.
    public var request: BuildRequest?

    public init(repository: BuildRepository? = nil, request: BuildRequest? = nil) {
        self.repository = repository
        self.request = request
    }
}

public struct BuildRequest: Codable, Equatable, Sendable {
    public var requestedAt: Date
    /// Known once GitHub lists the run.
    public var run: BuildRun?

    public init(requestedAt: Date, run: BuildRun? = nil) {
        self.requestedAt = requestedAt
        self.run = run
    }
}

/// Saves `BuilderState` and the GitHub token for Builder.
public protocol BuilderStorage: Sendable {
    func loadState() throws -> BuilderState
    func saveState(_ state: BuilderState) throws
    func token() throws -> String?
    func setToken(_ token: String?) throws
}

public enum BuildProgress: Equatable, Sendable {
    case none
    /// Requested, but GitHub has not listed the run yet.
    case waiting(since: Date)
    case running(BuildRun)
    case finished(BuildRun)

    public init(_ request: BuildRequest?) {
        guard let request else { self = .none; return }
        guard let run = request.run else { self = .waiting(since: request.requestedAt); return }
        self = run.isFinished ? .finished(run) : .running(run)
    }
}

/// How long a quick build usually takes, including runner queueing.
public enum BuildTiming {
    public static let expectedDuration: TimeInterval = 4 * 60
    /// A request that GitHub still has not listed after this is reported as lost.
    public static let startTimeout: TimeInterval = 10 * 60
    /// Allows for a different clock on this device and on GitHub.
    public static let clockTolerance: TimeInterval = 2 * 60
}

public enum BuildTrackingError: Error, Equatable, LocalizedError {
    case didNotStart

    public var errorDescription: String? {
        BuilderText.localized("GitHub did not start the build. Check the repository's Actions page.")
    }
}

extension GitHubBuildClient {
    /// Returns `request` with the latest state of its run.
    public func refresh(_ request: BuildRequest, now: Date = Date()) async throws -> BuildRequest {
        var request = request
        if let run = request.run {
            if !run.isFinished { request.run = try await self.run(id: run.id) }
        } else if let run = try await latestRun(since: request.requestedAt - BuildTiming.clockTolerance) {
            request.run = run
        } else if now.timeIntervalSince(request.requestedAt) > BuildTiming.startTimeout {
            throw BuildTrackingError.didNotStart
        }
        return request
    }
}
