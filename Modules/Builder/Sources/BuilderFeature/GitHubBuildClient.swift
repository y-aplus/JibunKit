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

public enum BuildClientError: Error, Equatable, LocalizedError {
    case invalidToken
    case forbidden(String)
    case notFound
    case rejected(String)
    case server(Int)
    case missingIPA
    case invalidResponse

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
    public static let ipaName = "JibunKit.ipa"

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
        let body = try JSONSerialization.data(withJSONObject: [
            "ref": repository.branch, "inputs": ["publish": "true"],
        ])
        _ = try await send(path: "actions/workflows/\(Self.workflow)/dispatches", method: "POST", body: body)
    }

    /// The newest run of the workflow on the branch created at or after `since`.
    public func latestRun(since: Date) async throws -> BuildRun? {
        let query = [URLQueryItem(name: "branch", value: repository.branch),
                     URLQueryItem(name: "event", value: "workflow_dispatch"),
                     URLQueryItem(name: "per_page", value: "10")]
        let data = try await send(path: "actions/workflows/\(Self.workflow)/runs", query: query)
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
        var request = authorized(URLRequest(url: asset.url), accept: "application/octet-stream")
        request.httpMethod = "GET"
        // The API redirects to storage that must not receive the GitHub token.
        var (data, response) = try await transport.data(for: request, followRedirects: false)
        if (300..<400).contains(response.statusCode) {
            guard let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
                throw BuildClientError.invalidResponse
            }
            (data, response) = try await transport.data(for: URLRequest(url: url), followRedirects: true)
        }
        try check(response, data: data)
        guard !data.isEmpty else { throw BuildClientError.missingIPA }
        try data.write(to: destination, options: .atomic)
    }

    private func authorized(_ request: URLRequest, accept: String = "application/vnd.github+json") -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func send(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository.owner)/\(repository.name)/\(path)"
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BuildClientError.invalidResponse }
        var request = authorized(URLRequest(url: url))
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
