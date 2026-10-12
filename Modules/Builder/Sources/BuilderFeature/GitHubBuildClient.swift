import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The GitHub repository and branch whose "Build IPA (quick)" workflow builds
/// this JibunKit.
public struct BuildRepository: Codable, Equatable, Sendable {
    public var owner: String
    public var name: String
    public var branch: String

    public init(owner: String, name: String, branch: String) {
        self.owner = owner
        self.name = name
        self.branch = branch
    }

    /// Accepts `OWNER/REPO`, optionally as a github.com URL.
    public init?(slug: String, branch: String) {
        var text = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasSuffix(".git") { text.removeLast(4) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count == 2 else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]), branch: branch.isEmpty ? "main" : branch)
        guard isValid else { return nil }
    }

    public var slug: String { "\(owner)/\(name)" }

    /// GitHub's form for a new fine-grained token with this owner, the name and
    /// the permissions Builder needs filled in. GitHub cannot pre-select the
    /// repository; the user chooses it under Repository access.
    /// https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
    public var tokenCreationURL: URL {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "JibunKit Build"),
            URLQueryItem(name: "description", value: "Starts the Build IPA (quick) workflow of \(slug) from JibunKit"),
            URLQueryItem(name: "target_name", value: owner),
            URLQueryItem(name: "expires_in", value: "90"),
            URLQueryItem(name: "actions", value: "write"),
            URLQueryItem(name: "contents", value: "read"),
        ]
        return components.url!
    }

    public var isValid: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return [owner, name].allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
            && !branch.isEmpty && !branch.contains("..") && !branch.hasPrefix("/")
    }
}

/// One run of the quick build workflow.
public struct BuildRun: Codable, Equatable, Sendable {
    public let id: Int
    public let status: String
    public let conclusion: String?
    public let createdAt: Date
    public let htmlURL: URL

    public init(id: Int, status: String, conclusion: String?, createdAt: Date, htmlURL: URL) {
        self.id = id
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.htmlURL = htmlURL
    }

    public var isFinished: Bool { status == "completed" }
    public var succeeded: Bool { isFinished && conclusion == "success" }

    enum CodingKeys: String, CodingKey {
        case id, status, conclusion
        case createdAt = "created_at"
        case htmlURL = "html_url"
    }
}

/// A Feature copied from another repository, as recorded in the host's
/// JibunKitImports.json by `Tools/jibunkit-feature.py add`.
public struct ImportedFeature: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var repository: String
    public var ref: String
    public var commit: String
    public var path: String

    public init(name: String, repository: String, ref: String, commit: String, path: String) {
        self.name = name
        self.repository = repository
        self.ref = ref
        self.commit = commit
        self.path = path
    }

    public var id: String { name }
}

/// One run of the Import Feature workflow.
public enum FeatureImportOperation: Codable, Equatable, Sendable {
    /// Empty strings leave the choice to the tool: the default branch, the
    /// repository root and a name derived from the path or URL.
    case add(repository: String, ref: String, path: String, name: String)
    /// An empty ref keeps the recorded one.
    case update(name: String, ref: String)
    case remove(name: String)

    public var inputs: [String: String] {
        switch self {
        case let .add(repository, ref, path, name):
            ["operation": "add", "repository": repository, "ref": ref, "path": path, "name": name]
        case let .update(name, ref):
            ["operation": "update", "name": name, "ref": ref]
        case let .remove(name):
            ["operation": "remove", "name": name]
        }
    }
}

public enum BuildClientError: Error, Equatable, LocalizedError {
    case invalidToken
    case forbidden(String)
    case notFound
    case rejected(String)
    case server(Int)
    case missingIPA
    case invalidResponse
    case missingImportWorkflow

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            BuilderText.localized("GitHub did not accept the token. Enter a new one.")
        case .forbidden(let message):
            BuilderText.localized("The token lacks a permission: %@", message)
        case .notFound:
            BuilderText.localized("The repository or its quick build workflow was not found, or the token cannot see it.")
        case .rejected(let message):
            BuilderText.localized("GitHub rejected the request: %@", message)
        case .server(let status):
            BuilderText.localized("GitHub returned HTTP %lld. Try again later.", status)
        case .missingIPA:
            BuilderText.localized("The build finished, but its IPA was not found.")
        case .invalidResponse:
            BuilderText.localized("GitHub returned an unexpected response.")
        case .missingImportWorkflow:
            BuilderText.localized("The repository has no Import Feature workflow. Update it from JibunKit first.")
        }
    }
}

/// Sends one HTTP request. `followRedirects: false` returns a redirect itself.
public protocol BuildHTTPTransport: Sendable {
    func data(for request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse)
}

/// Starts the repository's quick build, follows it and fetches its IPA through
/// the GitHub REST API.
public struct GitHubBuildClient: Sendable {
    public static let workflow = "quick-ipa.yml"
    public static let importWorkflow = "import-feature.yml"
    public static let ipaName = "JibunKit.ipa"
    public static let importsFile = "JibunKitImports.json"
    /// import-feature.yml prints the tool's output between these lines.
    static let reportStart = "=== JibunKit import report ==="
    static let reportEnd = "=== end of report ==="

    public let repository: BuildRepository
    private let token: String
    private let transport: any BuildHTTPTransport

    public init(repository: BuildRepository, token: String, transport: any BuildHTTPTransport) {
        self.repository = repository
        self.token = token
        self.transport = transport
    }

    /// Asks GitHub to run the workflow with `publish`, which attaches the IPA
    /// to the `build-RUN_ID` prerelease.
    public func requestBuild() async throws {
        try await dispatch(workflow: Self.workflow, inputs: ["publish": "true"])
    }

    /// Asks GitHub to run Import Feature, which commits the result to the branch.
    public func requestImport(_ operation: FeatureImportOperation) async throws {
        do {
            try await dispatch(workflow: Self.importWorkflow, inputs: operation.inputs)
        } catch BuildClientError.notFound {
            throw BuildClientError.missingImportWorkflow
        }
    }

    private func dispatch(workflow: String, inputs: [String: String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["ref": repository.branch, "inputs": inputs] as [String: Any])
        _ = try await send(path: "actions/workflows/\(workflow)/dispatches", method: "POST", body: body)
    }

    /// The newest run of the workflow on the branch created at or after `since`.
    public func latestRun(workflow: String = Self.workflow, since: Date) async throws -> BuildRun? {
        let query = [URLQueryItem(name: "branch", value: repository.branch),
                     URLQueryItem(name: "event", value: "workflow_dispatch"),
                     URLQueryItem(name: "per_page", value: "10")]
        let data = try await send(path: "actions/workflows/\(workflow)/runs", query: query)
        struct Runs: Decodable { let workflow_runs: [BuildRun] }
        return try decode(Runs.self, from: data).workflow_runs
            .filter { $0.createdAt >= since }
            .max { $0.createdAt < $1.createdAt }
    }

    public func run(id: Int) async throws -> BuildRun {
        try decode(BuildRun.self, from: try await send(path: "actions/runs/\(id)"))
    }

    /// Writes the run's IPA to `destination`.
    public func downloadIPA(runID: Int, to destination: URL) async throws {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let url: URL }
            let assets: [Asset]
        }
        let release: Release
        do {
            release = try decode(Release.self, from: try await send(path: "releases/tags/build-\(runID)"))
        } catch BuildClientError.notFound {
            throw BuildClientError.missingIPA
        }
        guard let asset = release.assets.first(where: { $0.name == Self.ipaName }) else {
            throw BuildClientError.missingIPA
        }
        let data = try await downloadFromStorage(authorized(URLRequest(url: asset.url), accept: "application/octet-stream"))
        guard !data.isEmpty else { throw BuildClientError.missingIPA }
        try data.write(to: destination, options: .atomic)
    }

    /// The Features recorded in the branch's JibunKitImports.json; none when it has no such file.
    public func importedFeatures() async throws -> [ImportedFeature] {
        struct Imports: Decodable {
            struct Entry: Decodable { let repository, ref, commit, path: String }
            let features: [String: Entry]
        }
        let data: Data
        do {
            data = try await send(path: "contents/\(Self.importsFile)", query: [URLQueryItem(name: "ref", value: repository.branch)],
                                  accept: "application/vnd.github.raw+json")
        } catch BuildClientError.notFound {
            return []
        }
        return try decode(Imports.self, from: data).features
            .map { ImportedFeature(name: $0.key, repository: $0.value.repository, ref: $0.value.ref,
                                   commit: $0.value.commit, path: $0.value.path) }
            .sorted { $0.name < $1.name }
    }

    /// What the tool printed in a finished Import Feature run, read from its log.
    public func importReport(runID: Int) async throws -> String? {
        struct Jobs: Decodable {
            struct Job: Decodable { let id: Int }
            let jobs: [Job]
        }
        guard let job = try decode(Jobs.self, from: try await send(path: "actions/runs/\(runID)/jobs")).jobs.first else {
            return nil
        }
        let url = try endpoint(path: "actions/jobs/\(job.id)/logs")
        let log = try await downloadFromStorage(authorized(URLRequest(url: url)))
        return Self.report(fromLog: String(decoding: log, as: UTF8.self))
    }

    /// The lines between the report markers, without the timestamp GitHub puts before each line.
    static func report(fromLog log: String) -> String? {
        var lines: [Substring]?
        // A Swift Character holds "\r\n" whole, so split on any line break.
        for line in log.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var text = line
            let stamp = text.prefix { $0 != " " }
            if stamp.count >= 20, stamp.first?.isNumber == true, stamp.last == "Z", stamp.contains("T") {
                text = text.dropFirst(stamp.count).drop { $0 == " " }
            }
            if text == Self.reportStart {
                lines = []
            } else if text == Self.reportEnd, let found = lines {
                return found.joined(separator: "\n")
            } else {
                lines?.append(text)
            }
        }
        return lines?.joined(separator: "\n")
    }

    /// The API redirects downloads to storage that must not receive the GitHub token.
    private func downloadFromStorage(_ request: URLRequest) async throws -> Data {
        var (data, response) = try await transport.data(for: request, followRedirects: false)
        if (300..<400).contains(response.statusCode) {
            guard let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
                throw BuildClientError.invalidResponse
            }
            (data, response) = try await transport.data(for: URLRequest(url: url), followRedirects: true)
        }
        try check(response, data: data)
        return data
    }

    private func authorized(_ request: URLRequest, accept: String = "application/vnd.github+json") -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func endpoint(path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository.owner)/\(repository.name)/\(path)"
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BuildClientError.invalidResponse }
        return url
    }

    private func send(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                      accept: String = "application/vnd.github+json") async throws -> Data {
        var request = authorized(URLRequest(url: try endpoint(path: path, query: query)), accept: accept)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.data(for: request, followRedirects: true)
        try check(response, data: data)
        return data
    }

    private func check(_ response: HTTPURLResponse, data: Data) throws {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
        switch response.statusCode {
        case 200..<300: return
        case 401: throw BuildClientError.invalidToken
        case 403: throw BuildClientError.forbidden(message)
        case 404: throw BuildClientError.notFound
        case 422: throw BuildClientError.rejected(message)
        default: throw BuildClientError.server(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(type, from: data) } catch { throw BuildClientError.invalidResponse }
    }
}

#if canImport(Darwin)
/// A transport on an ephemeral session, so no cookie, credential or cache is
/// shared with other Features.
public final class URLSessionBuildTransport: NSObject, BuildHTTPTransport, URLSessionTaskDelegate {
    private let session = URLSession(configuration: .ephemeral)

    public override init() {}

    public func data(for request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: followRedirects ? nil : self)
        guard let response = response as? HTTPURLResponse else { throw BuildClientError.invalidResponse }
        return (data, response)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
#endif
