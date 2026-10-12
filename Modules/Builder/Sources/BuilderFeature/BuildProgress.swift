import Foundation

/// What Builder remembers between launches. The token is stored separately.
public struct BuilderState: Codable, Equatable, Sendable {
    public var repository: BuildRepository?
    /// The last build this app requested, kept until another one starts.
    public var request: BuildRequest?
    /// The last import, update or removal this app requested.
    public var importRequest: ImportRequest?

    public init(repository: BuildRepository? = nil, request: BuildRequest? = nil, importRequest: ImportRequest? = nil) {
        self.repository = repository
        self.request = request
        self.importRequest = importRequest
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

public struct ImportRequest: Codable, Equatable, Sendable {
    public var operation: FeatureImportOperation
    public var requestedAt: Date
    public var run: BuildRun?
    /// The tool's output, read from the run's log after it finished.
    public var report: String?

    public init(operation: FeatureImportOperation, requestedAt: Date, run: BuildRun? = nil, report: String? = nil) {
        self.operation = operation
        self.requestedAt = requestedAt
        self.run = run
        self.report = report
    }

    public var progress: BuildProgress { BuildProgress(BuildRequest(requestedAt: requestedAt, run: run)) }
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
    case importDidNotStart

    public var errorDescription: String? {
        switch self {
        case .didNotStart:
            BuilderText.localized("GitHub did not start the build. Check the repository's Actions page.")
        case .importDidNotStart:
            BuilderText.localized("GitHub did not start the import. Check the repository's Actions page.")
        }
    }
}

extension GitHubBuildClient {
    /// Returns `request` with the latest state of its run.
    public func refresh(_ request: BuildRequest, now: Date = Date()) async throws -> BuildRequest {
        var request = request
        request.run = try await track(request.run, workflow: Self.workflow, requestedAt: request.requestedAt, now: now,
                                      lost: .didNotStart)
        return request
    }

    /// Returns `request` with the latest state of its run and, once it has
    /// finished, the tool's report.
    public func refresh(_ request: ImportRequest, now: Date = Date()) async throws -> ImportRequest {
        var request = request
        request.run = try await track(request.run, workflow: Self.importWorkflow, requestedAt: request.requestedAt,
                                      now: now, lost: .importDidNotStart)
        if let run = request.run, run.isFinished, request.report == nil {
            // GitHub may need a moment to publish the log; a later refresh tries again.
            request.report = try? await importReport(runID: run.id)
        }
        return request
    }

    private func track(_ run: BuildRun?, workflow: String, requestedAt: Date, now: Date,
                       lost: BuildTrackingError) async throws -> BuildRun? {
        if let run {
            return run.isFinished ? run : try await self.run(id: run.id)
        }
        if let run = try await latestRun(workflow: workflow, since: requestedAt - BuildTiming.clockTolerance) {
            return run
        }
        if now.timeIntervalSince(requestedAt) > BuildTiming.startTimeout { throw lost }
        return nil
    }
}
