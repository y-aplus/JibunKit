import Foundation
import XCTest
@testable import BuilderFeature

final class MemoryStorage: BuilderStorage, @unchecked Sendable {
    var state: BuilderState
    var savedToken: String?

    init(state: BuilderState, token: String?) {
        self.state = state
        savedToken = token
    }

    func loadState() throws -> BuilderState { state }
    func saveState(_ state: BuilderState) throws { self.state = state }
    func token() throws -> String? { savedToken }
    func setToken(_ token: String?) throws { savedToken = token }
}

final class BuiltIPATests: XCTestCase {
    let repository = BuildRepository(owner: "owner", name: "host", branch: "main")
    let created = ISO8601DateFormatter().date(from: "2026-10-20T07:10:03Z")!
    var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("builder-ipa-\(UUID())", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func storage(run: BuildRun?, token: String? = "secret") -> MemoryStorage {
        MemoryStorage(state: BuilderState(repository: repository, request: BuildRequest(requestedAt: created, run: run)), token: token)
    }

    func latest(_ storage: MemoryStorage, _ transport: StubTransport) async throws -> URL {
        try await BuiltIPA.latest(storage: storage, transport: transport, ipaDirectory: directory, now: created + 60)
    }

    func error(of operation: () async throws -> URL) async -> BuiltIPAError? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error as? BuiltIPAError
        }
    }

    func testARunningBuildIsFollowedAndItsIPADownloadedOnce() async throws {
        let storage = storage(run: BuildRun(id: 42, status: "in_progress", conclusion: nil, created: created))
        let release = #"{"assets": [{"name": "JibunKit.ipa", "url": "https://api.github.com/repos/owner/host/releases/assets/2"}]}"#
        let transport = StubTransport([
            ("/actions/runs/42", .init(status: 200, body: """
                {"id": 42, "status": "completed", "conclusion": "success", "created_at": "2026-10-20T07:10:03Z",
                 "html_url": "https://github.com/owner/host/actions/runs/42"}
                """)),
            ("/releases/tags/build-42", .init(status: 200, body: release)),
            ("/releases/assets/2", .init(status: 302, headers: ["Location": "https://objects.example/ipa"])),
            ("objects.example", .init(status: 200, body: "IPA")),
        ])
        let file = try await latest(storage, transport)
        XCTAssertEqual(file, BuiltIPA.file(for: try XCTUnwrap(storage.state.request?.run), in: directory))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "IPA")
        XCTAssertEqual(storage.state.request?.run?.succeeded, true)

        // The next call uses the downloaded file without asking GitHub.
        let idle = StubTransport([])
        let again = try await latest(storage, idle)
        XCTAssertEqual(again, file)
        XCTAssertTrue(idle.requests.isEmpty)
    }

    func testWhatStopsTheShortcutIsNamed() async {
        let finished = { (conclusion: String) in BuildRun(id: 7, status: "completed", conclusion: conclusion, created: self.created) }
        let unconfigured = storage(run: finished("success"), token: nil)
        let none = MemoryStorage(state: BuilderState(repository: repository), token: "secret")
        let failed = storage(run: finished("failure"))
        let running = storage(run: BuildRun(id: 7, status: "in_progress", conclusion: nil, created: created))
        let stillRunning = StubTransport([("/actions/runs/7", .init(status: 200, body: """
            {"id": 7, "status": "in_progress", "conclusion": null, "created_at": "2026-10-20T07:10:03Z",
             "html_url": "https://github.com/owner/host/actions/runs/7"}
            """))])

        let noRequests = StubTransport([])
        var result = await error { try await self.latest(unconfigured, noRequests) }
        XCTAssertEqual(result, .notConfigured)
        result = await error { try await self.latest(none, noRequests) }
        XCTAssertEqual(result, .noBuild)
        result = await error { try await self.latest(failed, noRequests) }
        XCTAssertEqual(result, .failed)
        result = await error { try await self.latest(running, stillRunning) }
        XCTAssertEqual(result, .building)
        XCTAssertTrue(noRequests.requests.isEmpty)
    }

    func testTheShortcutURLRunsTheNamedShortcut() throws {
        let url = BuiltIPA.shortcutURL(named: "JibunKitをインストール")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "run-shortcut")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: "JibunKitをインストール")])
    }
}
