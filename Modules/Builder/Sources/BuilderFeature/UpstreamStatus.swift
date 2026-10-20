import Foundation

extension BuildRepository {
    /// Public JibunKit, which a derived repository merges from unless the
    /// settings name another upstream.
    public static let defaultUpstream = BuildRepository(owner: "y-aplus", name: "JibunKit", branch: "main")
}

/// How far this repository is behind its upstream.
public struct UpstreamStatus: Equatable, Sendable {
    public var upstream: BuildRepository
    /// The upstream commits this repository does not have yet; nil when it
    /// has none of the newest `UpstreamStatus.counted`.
    public var newCommits: Int?
    /// The newest upstream commit this repository has.
    public var mergedCommit: String?
    /// The tag of upstream's latest release, which excludes prereleases.
    public var latestRelease: String?

    public static let counted = 100

    public init(upstream: BuildRepository, newCommits: Int?, mergedCommit: String?, latestRelease: String?) {
        self.upstream = upstream
        self.newCommits = newCommits
        self.mergedCommit = mergedCommit
        self.latestRelease = latestRelease
    }

    /// Upstream's changes since the merged commit, or its recent commits when none is merged.
    public var changesURL: URL {
        let base = "https://github.com/\(upstream.slug)"
        if let mergedCommit {
            return URL(string: "\(base)/compare/\(mergedCommit)...\(upstream.branch)")!
        }
        return URL(string: "\(base)/commits/\(upstream.branch)")!
    }
}

extension GitHubBuildClient {
    /// Compares this repository with `upstream`. A derived repository is not a
    /// GitHub fork, so GitHub cannot compare across the two; instead this asks
    /// which of upstream's newest commits this repository has. Upstream's
    /// branch is assumed to grow by appending, so once a commit is merged so
    /// are the older ones, and a binary search finds the newest merged one.
    public func upstreamStatus(of upstream: BuildRepository) async throws -> UpstreamStatus {
        struct Commit: Decodable { let sha: String }
        let commits = try decode([Commit].self, from: try await send(
            path: "commits", query: [URLQueryItem(name: "sha", value: upstream.branch),
                                     URLQueryItem(name: "per_page", value: String(UpstreamStatus.counted))],
            in: upstream)).map(\.sha)
        let release = try await latestRelease(of: upstream)
        guard let newest = commits.first else {
            return UpstreamStatus(upstream: upstream, newCommits: 0, mergedCommit: nil, latestRelease: release)
        }
        if try await hasCommit(newest) {
            return UpstreamStatus(upstream: upstream, newCommits: 0, mergedCommit: newest, latestRelease: release)
        }
        guard let oldest = commits.last, commits.count > 1, try await hasCommit(oldest) else {
            // Upstream's whole history is listed when it is shorter than a page.
            let all = commits.count < UpstreamStatus.counted
            return UpstreamStatus(upstream: upstream, newCommits: all ? commits.count : nil, mergedCommit: nil,
                                  latestRelease: release)
        }
        // commits[low] is missing here and commits[high] is merged.
        var low = 0, high = commits.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if try await hasCommit(commits[middle]) { high = middle } else { low = middle }
        }
        return UpstreamStatus(upstream: upstream, newCommits: high, mergedCommit: commits[high], latestRelease: release)
    }

    private func latestRelease(of upstream: BuildRepository) async throws -> String? {
        struct Release: Decodable { let tag_name: String }
        do {
            return try decode(Release.self, from: try await send(path: "releases/latest", in: upstream)).tag_name
        } catch BuildClientError.notFound {
            return nil
        }
    }

    /// GitHub answers 422 or 404 for a commit the repository does not have.
    private func hasCommit(_ sha: String) async throws -> Bool {
        do {
            _ = try await send(path: "commits/\(sha)", accept: "application/vnd.github.sha")
            return true
        } catch BuildClientError.notFound {
            return false
        } catch BuildClientError.rejected {
            return false
        }
    }
}
