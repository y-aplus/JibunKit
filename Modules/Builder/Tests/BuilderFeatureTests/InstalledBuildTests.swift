import Foundation
import XCTest
@testable import BuilderFeature

final class InstalledBuildTests: XCTestCase {
    let installed = InstalledBuild(runID: 100, commit: "abc")

    func client(_ transport: StubTransport) -> GitHubBuildClient {
        GitHubBuildClient(repository: BuildRepository(owner: "owner", name: "host", branch: "main"), token: "secret",
                          transport: transport)
    }

    func release(_ tag: String, prerelease: Bool = true, assets: [String] = ["JibunKit.ipa"]) -> String {
        let assets = assets.map { #"{"name": "\#($0)"}"# }.joined(separator: ",")
        return #"{"tag_name": "\#(tag)", "prerelease": \#(prerelease), "assets": [\#(assets)]}"#
    }

    func run(_ id: Int, branch: String = "main", conclusion: String = "success") -> StubTransport.Reply {
        .init(status: 200, body: """
        {"id": \(id), "status": "completed", "conclusion": "\(conclusion)", "created_at": "2026-11-04T01:02:03Z",
         "html_url": "https://github.com/owner/host/actions/runs/\(id)", "head_branch": "\(branch)"}
        """)
    }

    func testReadsTheRunIDFromInfoPlist() {
        XCTAssertEqual(InstalledBuild(infoDictionary: [InstalledBuild.runIDKey: "123", InstalledBuild.commitKey: "abc"]),
                       InstalledBuild(runID: 123, commit: "abc"))
        XCTAssertEqual(InstalledBuild(infoDictionary: [InstalledBuild.runIDKey: "123"])?.commit, "")
        XCTAssertNil(InstalledBuild(infoDictionary: [:]))
        XCTAssertNil(InstalledBuild(infoDictionary: nil))
        XCTAssertNil(InstalledBuild(infoDictionary: [InstalledBuild.runIDKey: ""]))
        XCTAssertNil(InstalledBuild(infoDictionary: [InstalledBuild.runIDKey: "0"]))
    }

    func testFindsTheNewestBuildOfTheBranch() async throws {
        let releases = "[" + [release("build-130"), release("build-120"), release("launch-140"), release("v1.2.0", prerelease: false),
                              release("build-110", assets: ["JibunKit-dSYMs.zip"]), release("build-90")].joined(separator: ",") + "]"
        let transport = StubTransport([
            ("/repos/owner/host/releases?per_page=30", .init(status: 200, body: releases)),
            ("/actions/runs/130", run(130, branch: "feature")),
            ("/actions/runs/120", run(120)),
        ])
        let newer = try await client(transport).newerBuild(than: installed)
        XCTAssertEqual(newer?.id, 120)
        XCTAssertEqual(transport.requests.count, 3, "build-110 has no IPA and build-90 is older")
    }

    func testSkipsFailedAndMissingRuns() async throws {
        let releases = "[" + [release("build-130"), release("build-120")].joined(separator: ",") + "]"
        let transport = StubTransport([
            ("/releases?per_page=30", .init(status: 200, body: releases)),
            ("/actions/runs/130", .init(status: 404)),
            ("/actions/runs/120", run(120, conclusion: "failure")),
        ])
        let newer = try await client(transport).newerBuild(than: installed)
        XCTAssertNil(newer)
    }

    func testNoNewerBuildAsksOnlyForReleases() async throws {
        let transport = StubTransport([("/releases?per_page=30", .init(status: 200, body: "[" + release("build-100") + "]"))])
        let newer = try await client(transport).newerBuild(than: installed)
        XCTAssertNil(newer)
        XCTAssertEqual(transport.requests.count, 1)
    }
}
