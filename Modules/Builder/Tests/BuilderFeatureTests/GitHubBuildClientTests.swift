import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BuilderFeature

/// Answers requests from a table and records what was sent.
final class StubTransport: BuildHTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int; var body: String = ""; var headers: [String: String] = [:] }
    private let lock = NSLock()
    private var replies: [(match: String, reply: Reply)]
    private(set) var requests: [(request: URLRequest, followRedirects: Bool)] = []

    init(_ replies: [(String, Reply)]) { self.replies = replies.map { (match: $0.0, reply: $0.1) } }

    func data(for request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock {
            requests.append((request, followRedirects))
            let url = request.url!.absoluteString
            guard let index = replies.firstIndex(where: { url.contains($0.match) }) else {
                XCTFail("Unexpected request \(url)")
                throw URLError(.badURL)
            }
            let reply = replies.remove(at: index).reply
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                           headerFields: reply.headers)!
            return (Data(reply.body.utf8), response)
        }
    }
}

final class GitHubBuildClientTests: XCTestCase {
    let repository = BuildRepository(owner: "owner", name: "host", branch: "main")

    func client(_ transport: StubTransport) -> GitHubBuildClient {
        GitHubBuildClient(repository: repository, token: "secret", transport: transport)
    }

    func runJSON(id: Int, status: String, conclusion: String?, created: String) -> String {
        let conclusion = conclusion.map { "\"\($0)\"" } ?? "null"
        return """
        {"id": \(id), "status": "\(status)", "conclusion": \(conclusion), "created_at": "\(created)",
         "html_url": "https://github.com/owner/host/actions/runs/\(id)"}
        """
    }

    func testRepositoryParsing() {
        XCTAssertEqual(BuildRepository(slug: "owner/host", branch: ""), BuildRepository(owner: "owner", name: "host", branch: "main"))
        XCTAssertEqual(BuildRepository(slug: " https://github.com/owner/host.git ", branch: "dev")?.slug, "owner/host")
        XCTAssertNil(BuildRepository(slug: "owner", branch: "main"))
        XCTAssertNil(BuildRepository(slug: "owner/host/extra", branch: "main"))
        XCTAssertNil(BuildRepository(slug: "own er/host", branch: "main"))
        XCTAssertNil(BuildRepository(slug: "owner/host", branch: "a..b"))
    }

    func testTokenCreationURLNamesTheRepositoryOwnerAndPermissions() throws {
        let url = BuildRepository(owner: "someone", name: "my-host", branch: "main").tokenCreationURL
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/settings/personal-access-tokens/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["target_name"], "someone")
        XCTAssertEqual(items["actions"], "write")
        XCTAssertEqual(items["contents"], "read")
        XCTAssertTrue(items["description"]?.contains("someone/my-host") ?? false)
    }

    func testRequestBuildDispatchesThePublishingWorkflow() async throws {
        let transport = StubTransport([("/dispatches", .init(status: 204))])
        try await client(transport).requestBuild()
        let request = try XCTUnwrap(transport.requests.first?.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/repos/owner/host/actions/workflows/quick-ipa.yml/dispatches")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["ref"] as? String, "main")
        XCTAssertEqual(body["inputs"] as? [String: String], ["publish": "true"])
    }

    func testHTTPErrorsAreNamed() async {
        let cases: [(Int, BuildClientError)] = [
            (401, .invalidToken), (403, .forbidden("Resource not accessible")), (404, .notFound),
            (422, .rejected("Resource not accessible")), (500, .server(500)),
        ]
        for (status, expected) in cases {
            let transport = StubTransport([("/dispatches", .init(status: status, body: #"{"message": "Resource not accessible"}"#))])
            do {
                try await client(transport).requestBuild()
                XCTFail("HTTP \(status) succeeded")
            } catch {
                XCTAssertEqual(error as? BuildClientError, expected)
            }
        }
    }

    func testRefreshFindsTheRunRequestedFromThisDevice() async throws {
        let requestedAt = ISO8601DateFormatter().date(from: "2026-10-11T07:10:00Z")!
        let list = """
        {"workflow_runs": [\(runJSON(id: 1, status: "completed", conclusion: "success", created: "2026-10-11T06:00:00Z")),
                           \(runJSON(id: 2, status: "in_progress", conclusion: nil, created: "2026-10-11T07:10:03Z"))]}
        """
        let transport = StubTransport([("/runs?", .init(status: 200, body: list))])
        let request = try await client(transport).refresh(BuildRequest(requestedAt: requestedAt), now: requestedAt + 10)
        XCTAssertEqual(request.run?.id, 2)
        XCTAssertEqual(BuildProgress(request), .running(request.run!))
        let query = transport.requests[0].request.url!.query!
        XCTAssertTrue(query.contains("branch=main") && query.contains("event=workflow_dispatch"), query)
    }

    func testRefreshFollowsAKnownRunUntilItFinishes() async throws {
        let created = ISO8601DateFormatter().date(from: "2026-10-11T07:10:03Z")!
        let running = BuildRun(id: 2, status: "in_progress", conclusion: nil, created: created)
        let transport = StubTransport([("/actions/runs/2", .init(status: 200, body: runJSON(
            id: 2, status: "completed", conclusion: "success", created: "2026-10-11T07:10:03Z")))])
        let request = try await client(transport).refresh(BuildRequest(requestedAt: created, run: running))
        XCTAssertEqual(request.run?.succeeded, true)

        // A finished run is not asked for again.
        let idle = StubTransport([])
        _ = try await client(idle).refresh(request)
        XCTAssertTrue(idle.requests.isEmpty)
    }

    func testARequestGitHubNeverListsIsReportedAfterTheTimeout() async throws {
        let requestedAt = Date(timeIntervalSince1970: 1_000_000)
        let empty = #"{"workflow_runs": []}"#
        let waiting = try await client(StubTransport([("/runs?", .init(status: 200, body: empty))]))
            .refresh(BuildRequest(requestedAt: requestedAt), now: requestedAt + 60)
        XCTAssertEqual(BuildProgress(waiting), .waiting(since: requestedAt))
        do {
            _ = try await client(StubTransport([("/runs?", .init(status: 200, body: empty))]))
                .refresh(BuildRequest(requestedAt: requestedAt), now: requestedAt + BuildTiming.startTimeout + 1)
            XCTFail("A lost request was not reported")
        } catch {
            XCTAssertEqual(error as? BuildTrackingError, .didNotStart)
        }
    }

    func testDownloadDoesNotSendTheTokenToTheRedirectTarget() async throws {
        let release = #"{"assets": [{"name": "other.txt", "url": "https://api.github.com/repos/owner/host/releases/assets/1"},"#
            + #" {"name": "JibunKit.ipa", "url": "https://api.github.com/repos/owner/host/releases/assets/2"}]}"#
        let transport = StubTransport([
            ("/releases/tags/build-42", .init(status: 200, body: release)),
            ("/releases/assets/2", .init(status: 302, headers: ["Location": "https://objects.example/ipa?signature=x"])),
            ("objects.example", .init(status: 200, body: "IPA")),
        ])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("builder-test-\(UUID()).ipa")
        defer { try? FileManager.default.removeItem(at: file) }
        try await client(transport).downloadIPA(runID: 42, to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "IPA")

        let asset = transport.requests[1]
        XCTAssertFalse(asset.followRedirects)
        XCTAssertEqual(asset.request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
        let storage = transport.requests[2].request
        XCTAssertNil(storage.value(forHTTPHeaderField: "Authorization"))
    }

    func testAMissingReleaseIsAMissingIPA() async {
        let transport = StubTransport([("/releases/tags/build-42", .init(status: 404))])
        do {
            try await client(transport).downloadIPA(runID: 42, to: FileManager.default.temporaryDirectory.appendingPathComponent("unused.ipa"))
            XCTFail("A missing release succeeded")
        } catch {
            XCTAssertEqual(error as? BuildClientError, .missingIPA)
        }
    }

    func testRequestImportDispatchesTheImportWorkflow() async throws {
        let transport = StubTransport([("/import-feature.yml/dispatches", .init(status: 204))])
        try await client(transport).requestImport(.add(repository: "https://github.com/someone/notes", ref: "",
                                                       path: "Modules/Notes", name: ""))
        let request = try XCTUnwrap(transport.requests.first?.request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["ref"] as? String, "main")
        XCTAssertEqual(body["inputs"] as? [String: String], [
            "operation": "add", "repository": "https://github.com/someone/notes", "ref": "", "path": "Modules/Notes", "name": "",
        ])
        XCTAssertEqual(FeatureImportOperation.update(name: "Notes", ref: "").inputs, ["operation": "update", "name": "Notes", "ref": ""])
        XCTAssertEqual(FeatureImportOperation.remove(name: "Notes").inputs, ["operation": "remove", "name": "Notes"])

        // A host made before the workflow existed.
        let missing = StubTransport([("/import-feature.yml/dispatches", .init(status: 404))])
        do {
            try await client(missing).requestImport(.remove(name: "Notes"))
            XCTFail("A missing workflow succeeded")
        } catch {
            XCTAssertEqual(error as? BuildClientError, .missingImportWorkflow)
        }
    }

    func testImportedFeaturesReadTheBranchRecord() async throws {
        let record = """
        {"schema": 1, "features": {
          "Notes": {"repository": "https://github.com/someone/notes", "ref": "HEAD", "commit": "\(String(repeating: "a", count: 40))", "path": ""},
          "Atlas": {"repository": "https://github.com/someone/apps", "ref": "v1", "commit": "\(String(repeating: "b", count: 40))", "path": "Modules/Atlas"}
        }}
        """
        let transport = StubTransport([("/contents/JibunKitImports.json", .init(status: 200, body: record))])
        let features = try await client(transport).importedFeatures()
        XCTAssertEqual(features.map(\.name), ["Atlas", "Notes"])
        XCTAssertEqual(features[0].path, "Modules/Atlas")
        let request = transport.requests[0].request
        XCTAssertEqual(request.url?.query, "ref=main")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")

        let none = StubTransport([("/contents/JibunKitImports.json", .init(status: 404))])
        let empty = try await client(none).importedFeatures()
        XCTAssertEqual(empty, [])
    }

    func testImportRefreshFollowsTheRunAndReadsTheReportFromItsLog() async throws {
        let requestedAt = ISO8601DateFormatter().date(from: "2026-10-12T07:00:00Z")!
        let operation = FeatureImportOperation.add(repository: "https://github.com/someone/notes", ref: "", path: "", name: "Notes")
        let list = #"{"workflow_runs": [\#(runJSON(id: 7, status: "queued", conclusion: nil, created: "2026-10-12T07:00:02Z"))]}"#
        let started = try await client(StubTransport([("/import-feature.yml/runs?", .init(status: 200, body: list))]))
            .refresh(ImportRequest(operation: operation, requestedAt: requestedAt), now: requestedAt + 5)
        XCTAssertEqual(started.progress, .running(started.run!))
        XCTAssertNil(started.report)

        let log = [
            "2026-10-12T07:00:20.1000000Z ##[group]Run set -uo pipefail",
            "2026-10-12T07:00:20.1000001Z \u{1B}[36;1mecho \"=== JibunKit import report ===\"\u{1B}[0m",
            "2026-10-12T07:00:21.0000000Z === JibunKit import report ===",
            "2026-10-12T07:00:21.0000001Z Copied https://github.com/someone/notes (root) at abc into Modules/Notes: 7 files, 12 KB",
            "2026-10-12T07:00:21.0000002Z ",
            "2026-10-12T07:00:21.0000003Z Updated Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift.",
            "2026-10-12T07:00:21.0000004Z === end of report ===",
            "2026-10-12T07:00:22.0000000Z Committed abc",
        ].joined(separator: "\r\n")
        let transport = StubTransport([
            ("/actions/runs/7/jobs", .init(status: 200, body: #"{"jobs": [{"id": 70}]}"#)),
            ("/actions/runs/7", .init(status: 200, body: runJSON(id: 7, status: "completed", conclusion: "success",
                                                                 created: "2026-10-12T07:00:02Z"))),
            ("/actions/jobs/70/logs", .init(status: 302, headers: ["Location": "https://logs.example/70?sig=x"])),
            ("logs.example", .init(status: 200, body: log)),
        ])
        let finished = try await client(transport).refresh(started)
        XCTAssertEqual(finished.run?.succeeded, true)
        XCTAssertEqual(finished.report, """
            Copied https://github.com/someone/notes (root) at abc into Modules/Notes: 7 files, 12 KB

            Updated Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift.
            """)
        XCTAssertNil(transport.requests.last?.request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(transport.requests[2].followRedirects)
    }

    func testAReportWithoutMarkersIsNil() {
        XCTAssertNil(GitHubBuildClient.report(fromLog: "2026-10-12T07:00:21.0000000Z Checking out\n"))
        XCTAssertEqual(GitHubBuildClient.report(fromLog: "=== JibunKit import report ===\nerror: stopped"), "error: stopped")
    }

    func testStateFromAnEarlierVersionStillDecodes() throws {
        let earlier = #"{"repository": {"owner": "owner", "name": "host", "branch": "main"}}"#
        let state = try JSONDecoder().decode(BuilderState.self, from: Data(earlier.utf8))
        XCTAssertEqual(state.repository, repository)
        XCTAssertNil(state.importRequest)

        let withImport = BuilderState(repository: repository, importRequest: ImportRequest(
            operation: .update(name: "Notes", ref: "v2"), requestedAt: Date(timeIntervalSince1970: 1_000_000), report: "done"))
        XCTAssertEqual(try JSONDecoder().decode(BuilderState.self, from: JSONEncoder().encode(withImport)), withImport)
    }

    func testStateRoundTrips() throws {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let state = BuilderState(repository: repository, request: BuildRequest(
            requestedAt: created, run: BuildRun(id: 2, status: "completed", conclusion: "failure", created: created)))
        let decoded = try JSONDecoder().decode(BuilderState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(BuildProgress(decoded.request), .finished(state.request!.run!))
        XCTAssertFalse(decoded.request!.run!.succeeded)
    }
}

extension BuildRun {
    init(id: Int, status: String, conclusion: String?, created: Date) {
        self.init(id: id, status: status, conclusion: conclusion, createdAt: created,
                  htmlURL: URL(string: "https://github.com/owner/host/actions/runs/\(id)")!)
    }
}
