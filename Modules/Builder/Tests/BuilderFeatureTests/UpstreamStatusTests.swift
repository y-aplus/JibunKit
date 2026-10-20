import Foundation
import XCTest
@testable import BuilderFeature

final class UpstreamStatusTests: XCTestCase {
    let downstream = BuildRepository(owner: "owner", name: "host", branch: "main")
    let upstream = BuildRepository.defaultUpstream

    func client(_ transport: StubTransport) -> GitHubBuildClient {
        GitHubBuildClient(repository: downstream, token: "secret", transport: transport)
    }

    /// Upstream's commits newest first, the release, and which commits the downstream has.
    func transport(commits: [String], merged: Set<String>, release: String?) -> StubTransport {
        let list = "[" + commits.map { #"{"sha": "\#($0)"}"# }.joined(separator: ",") + "]"
        var replies: [(String, StubTransport.Reply)] = [
            ("/repos/y-aplus/JibunKit/commits?", .init(status: 200, body: list)),
            ("/repos/y-aplus/JibunKit/releases/latest",
             release.map { .init(status: 200, body: #"{"tag_name": "\#($0)"}"#) } ?? .init(status: 404)),
        ]
        for sha in commits {
            replies.append(("/repos/owner/host/commits/\(sha)", merged.contains(sha)
                ? .init(status: 200, body: sha)
                : .init(status: 422, body: #"{"message": "No commit found for SHA: \#(sha)"}"#)))
        }
        return StubTransport(replies)
    }

    func testTheNewestMergedCommitIsFoundByBinarySearch() async throws {
        let commits = (0..<10).map { "c\($0)" }
        let transport = transport(commits: commits, merged: Set(commits[4...]), release: "v1.2.0")
        let status = try await client(transport).upstreamStatus(of: upstream)
        XCTAssertEqual(status, UpstreamStatus(upstream: upstream, newCommits: 4, mergedCommit: "c4", latestRelease: "v1.2.0"))
        XCTAssertEqual(status.changesURL.absoluteString, "https://github.com/y-aplus/JibunKit/compare/c4...main")
        let asked = transport.requests.filter { $0.request.url!.path.hasPrefix("/repos/owner/host/commits/") }
        XCTAssertLessThan(asked.count, 7)
        XCTAssertTrue(transport.requests.allSatisfy { $0.request.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
    }

    func testAnUpToDateRepositoryAsksOnce() async throws {
        let transport = transport(commits: ["c0", "c1", "c2"], merged: ["c0", "c1", "c2"], release: nil)
        let status = try await client(transport).upstreamStatus(of: upstream)
        XCTAssertEqual(status.newCommits, 0)
        XCTAssertEqual(status.mergedCommit, "c0")
        XCTAssertNil(status.latestRelease)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testNothingMergedFromAFullPageIsMoreThanCounted() async throws {
        let commits = (0..<UpstreamStatus.counted).map { "c\($0)" }
        let status = try await client(transport(commits: commits, merged: [], release: nil)).upstreamStatus(of: upstream)
        XCTAssertNil(status.newCommits)
        XCTAssertNil(status.mergedCommit)
        XCTAssertEqual(status.changesURL.absoluteString, "https://github.com/y-aplus/JibunKit/commits/main")

        // A shorter history is listed whole, so its commits can be counted.
        let short = try await client(transport(commits: ["c0", "c1"], merged: [], release: nil)).upstreamStatus(of: upstream)
        XCTAssertEqual(short.newCommits, 2)
    }

    func testStateWithoutAnUpstreamUsesTheDefault() throws {
        let data = Data(#"{"repository": {"owner": "owner", "name": "host", "branch": "main"}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(BuilderState.self, from: data).upstream)
    }
}
