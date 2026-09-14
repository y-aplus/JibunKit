// Copied only into the isolated 0.8 candidate host. Normal Definition,
// lifetime, store-access, and management-removal paths are intentionally used.
#if os(iOS)
import Foundation
import JibunKitCore
import Observation
import SwiftUI

@MainActor
enum P1HTTPProbe {
    private static let a = P1HTTPOwner(id: "p1-http-a", password: "owner-a-stable")
    private static let b = P1HTTPOwner(id: "p1-http-b", password: "owner-b-stable")
    static let ownerADefinition = definition(a, title: "HTTP ownership A")
    static let ownerBDefinition = definition(b, title: "HTTP ownership B")
    private static func definition(_ owner: P1HTTPOwner, title: String) -> MiniAppDefinition {
        MiniAppDefinition(id: owner.id, title: title, systemImage: "network", lifetime: owner.lifetime,
            removal: .init(id: owner.id, dataDescription: "HTTP Cookie、パスワード資格情報、応答cache",
                           removeData: { try await owner.removeOwnedData() })) { _ in P1HTTPProbeView(owner: owner) }
    }
}

@MainActor
@Observable
private final class P1HTTPOwner {
    let id: MiniAppID
    private let stablePassword: String
    var status = "ready"
    var cookie = "--"
    var authentication = "--"
    var cached = "--"
    var failNextSave = false
    @ObservationIgnored private var cookies: MiniAppCookieStore?
    @ObservationIgnored private var credentials: MiniAppPasswordCredentialStore?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var control: Task<Void, Never>?
    @ObservationIgnored private var holdToken: String?

    @ObservationIgnored lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }; try await self.openSession()
        try runtime.onShutdown { [weak self] in self?.closeSession() }
    }
    init(id: String, password: String) { self.id = MiniAppID(id); stablePassword = password }
    private var port: Int? { base?.port }
    private var base: URL?
    private var cacheRoot: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
    private var stableCookie: String { id.rawValue + "-stable" }

    private func openSession() async throws {
        let base: URL
        if let raw = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] {
            guard let port = UInt16(raw), port > 0 else { throw Failure.fixtureUnavailable }
            base = URL(string: "http://127.0.0.1:\(port)")!
        } else { base = try await P1DeviceHTTPFixture.shared.start() }
        let context = MiniAppContext(id: id)
        let cookies = try MiniAppCookieStore(context: context), credentials = try MiniAppPasswordCredentialStore(context: context)
        // A retained custom disk cache is evidence inside reconstructed sessions;
        // it is not an OS guarantee across a process replacement.
        let cache = try context.urlCache(memoryCapacity: 1_048_576, diskCapacity: 4_194_304, containerURL: cacheRoot)
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookies.storage; config.urlCredentialStorage = credentials.storage
        config.urlCache = cache; config.requestCachePolicy = .useProtocolCachePolicy
        self.base = base; self.cookies = cookies; self.credentials = credentials; session = URLSession(configuration: config)
    }
    private func closeSession() { session?.invalidateAndCancel(); session = nil; cookies = nil; credentials = nil; base = nil }

    func login() { startWriter("login") { [self] in try await performLogin(candidate: failNextSave) } }
    func reload() { startWriter("reload") { [self] in try await readState(checkCache: false) } }
    func readCache() { startWriter("cache") { [self] in try await readState(checkCache: true) } }
    func startHeldWrite() {
        startWriter("held-write") { [self] in
            guard let base, let session else { throw Failure.resourceLost }
            let token = id.rawValue + "-" + UUID().uuidString; holdToken = token
            let acknowledgement = URLSession(configuration: .ephemeral); defer { acknowledgement.invalidateAndCancel() }
            async let held: (Data, URLResponse) = session.data(from: base.appendingPathComponent("hold/" + token))
            let (_, started) = try await acknowledgement.data(from: base.appendingPathComponent("await-start/" + token)); try require(started, 200)
            status = "writer started"
            let (_, response) = try await held; try require(response, 200)
            guard let cookies else { throw Failure.resourceLost }; try cookies.save()
        }
    }
    func cancelHeldWrite() {
        guard let writer, let token = holdToken, control == nil else { status = "rejected: no held writer"; return }
        status = "cancelling held writer"; writer.cancel()
        do {
            guard let runtime = lifetime.runtime else { throw Failure.resourceLost }
            control = try runtime.start { [self] in await finishCancellation(writer, token: token) }
        } catch { status = "failed cancellation verification: \(error.localizedDescription)" }
    }
    private func finishCancellation(_ writer: Task<Void, Never>, token: String) async {
        await writer.value
        do {
            try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: id) { try await releaseAndVerify(token) }
            status = "cancelled held-write; no late cookie"
        } catch { status = "failed cancellation verification: \(error.localizedDescription)" }
        holdToken = nil; control = nil
    }
    func expectedHTTPFailure() {
        startWriter("unauthenticated-request") { [self] in
            guard let base else { throw Failure.fixtureUnavailable }
            let anonymous = URLSession(configuration: .ephemeral); defer { anonymous.invalidateAndCancel() }
            let (_, response) = try await anonymous.data(from: base.appendingPathComponent("auth"))
            guard try code(response) == 401 else { throw Failure.expectedHTTPFailureMissing }
            throw Failure.expectedHTTPFailure
        }
    }
    // The lifetime owns the stopped boundary, including concurrent restart and
    // management. The external caller must not be a task drained by that lifetime.
    func stopThenLogout() {
        guard control == nil, let base else { status = "rejected: control busy or unavailable"; return }
        status = "stopping writers for logout"
        control = Task { [self] in
            do {
                try await lifetime.withStoppedOperation { [self] in
                    try await MiniAppRestoreCoordinator.shared.withStoreMaintenance(for: id) { try await stoppedLogout(base: base) }
                }
                status = "logout completed; reopen to inspect"
            }
            catch { status = "logout failed: \(error.localizedDescription)" }
            control = nil
        }
    }
    func removeOwnedData() throws {
        precondition(lifetime.runtime == nil, "management must serialize stopped HTTP cleanup")
        let context = MiniAppContext(id: id)
        try MiniAppCookieStore(context: context).clear(); try MiniAppPasswordCredentialStore(context: context).clear()
        try context.urlCache(memoryCapacity: 0, diskCapacity: 4_194_304, containerURL: cacheRoot).removeAllCachedResponses()
        cookie = ""; authentication = "unauthenticated"; cached = ""
    }

    private func startWriter(_ label: String, _ operation: @escaping @MainActor @Sendable () async throws -> Void) {
        guard writer == nil, control == nil, let runtime = lifetime.runtime, !runtime.isClosed else { status = "rejected: unavailable"; return }
        status = "processing " + label; let owner = id
        do { writer = try runtime.start { [weak self] in
            do {
                try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: owner) { try await operation() }
                await self?.finish(label, cancelled: false, failure: nil)
            } catch {
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                await self?.finish(label, cancelled: cancelled, failure: cancelled ? nil : error.localizedDescription)
            }
        }} catch { status = "rejected: unavailable" }
    }
    private func finish(_ label: String, cancelled: Bool, failure: String?) {
        if cancelled { status = "cancelled " + label }
        else if let failure { status = "failed " + label + ": " + failure }
        else { status = "completed " + label }
        writer = nil
    }

    private func performLogin(candidate: Bool) async throws {
        guard let base, let session, let cookies, let credentials, let port else { throw Failure.resourceLost }
        let password = candidate ? stablePassword + "-candidate" : stablePassword
        let value = candidate ? id.rawValue + "-candidate" : stableCookie
        let space = URLProtectionSpace(host: "127.0.0.1", port: port, protocol: "http", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        credentials.storage.setDefaultCredential(.init(user: "account", password: password, persistence: .forSession), for: space)
        let (auth, authResponse) = try await session.data(from: base.appendingPathComponent("auth")); try require(authResponse, 200)
        var set = URLRequest(url: base.appendingPathComponent("set-persistent")); set.setValue(value, forHTTPHeaderField: "X-Fixture-Owner")
        let (_, setResponse) = try await session.data(for: set); try require(setResponse, 200)
        var cacheRequest = URLRequest(url: base.appendingPathComponent("cache/shared")); cacheRequest.setValue(value, forHTTPHeaderField: "X-Fixture-Owner")
        let (cacheData, cacheResponse) = try await session.data(for: cacheRequest); try require(cacheResponse, 200)
        if candidate && failNextSave {
            failNextSave = false
            // A deliberate precommit failure, not a simulated Keychain failure:
            // neither store is saved and no cross-store atomicity is claimed.
            try cookies.reload(); try credentials.reload()
            // Reconstruct to discard URLSession's remembered authentication
            // challenges as well as the candidate in-memory store values.
            closeSession(); try await openSession(); try await readState(checkCache: false)
            throw Failure.injectedPrecommitFailure
        }
        try cookies.save(); try credentials.save()
        cookie = try await echo(session, base); authentication = String(decoding: auth, as: UTF8.self); cached = String(decoding: cacheData, as: UTF8.self)
    }
    private func readState(checkCache: Bool) async throws {
        guard let base, let session else { throw Failure.resourceLost }
        cookie = try await echo(session, base)
        let (auth, response) = try await session.data(from: base.appendingPathComponent("auth")); let status = try code(response)
        guard status == 200 || status == 401 else { throw Failure.badResponse(status) }
        authentication = status == 200 ? String(decoding: auth, as: UTF8.self) : "unauthenticated"
        if checkCache { var request = URLRequest(url: base.appendingPathComponent("cache/shared")); request.cachePolicy = .returnCacheDataDontLoad; request.setValue("network-fallback", forHTTPHeaderField: "X-Fixture-Owner")
            let (data, response) = try await session.data(for: request); try require(response, 200); cached = String(decoding: data, as: UTF8.self) }
    }
    private func releaseAndVerify(_ token: String) async throws {
        guard let base, let session else { throw Failure.resourceLost }
        let (_, response) = try await session.data(from: base.appendingPathComponent("release/" + token)); try require(response, 200)
        cookie = try await echo(session, base)
        guard cookie == "account=" + stableCookie else { throw Failure.lateCookieResurrection }
    }
    private func stoppedLogout(base: URL) async throws {
        let context = MiniAppContext(id: id)
        let cookies = try MiniAppCookieStore(context: context), credentials = try MiniAppPasswordCredentialStore(context: context)
        let config = URLSessionConfiguration.default; config.httpCookieStorage = cookies.storage; config.urlCredentialStorage = credentials.storage; config.urlCache = nil
        let logout = URLSession(configuration: config); defer { logout.finishTasksAndInvalidate() }
        if let token = holdToken {
            let (_, released) = try await logout.data(from: base.appendingPathComponent("release/" + token))
            try require(released, 200)
            holdToken = nil
        }
        let (_, response) = try await logout.data(from: base.appendingPathComponent("logout")); try require(response, 200)
        try cookies.save(); try credentials.clear()
    }
    private func echo(_ session: URLSession, _ base: URL) async throws -> String { let (data, response) = try await session.data(from: base.appendingPathComponent("echo")); try require(response, 200); return String(decoding: data, as: UTF8.self) }
    private func code(_ response: URLResponse) throws -> Int { guard let http = response as? HTTPURLResponse else { throw Failure.nonHTTPResponse }; return http.statusCode }
    private func require(_ response: URLResponse, _ expected: Int) throws { let actual = try code(response); guard actual == expected else { throw Failure.badResponse(actual) } }
}

private enum Failure: LocalizedError { case fixtureUnavailable, resourceLost, nonHTTPResponse, badResponse(Int), injectedPrecommitFailure, expectedHTTPFailure, expectedHTTPFailureMissing, lateCookieResurrection
    var errorDescription: String? { switch self { case .fixtureUnavailable: "loopback fixture unavailable"; case .resourceLost: "HTTP resources unavailable"; case .nonHTTPResponse: "non-HTTP response"; case .badResponse(let code): "unexpected HTTP status \(code)"; case .injectedPrecommitFailure: "injected precommit failure; old durable snapshots restored"; case .expectedHTTPFailure: "expected unauthenticated HTTP failure"; case .expectedHTTPFailureMissing: "unauthenticated request unexpectedly succeeded"; case .lateCookieResurrection: "cancelled request applied a late cookie" } }
}

private struct P1HTTPProbeView: View { let owner: P1HTTPOwner; @Bindable private var state: P1HTTPOwner
    init(owner: P1HTTPOwner) { self.owner = owner; _state = Bindable(owner) }
    var body: some View { List { Section("状態") { Text(state.status).accessibilityIdentifier("p1.http.status"); Text(state.cookie.isEmpty ? "(empty)" : state.cookie).accessibilityIdentifier("p1.http.cookie"); Text(state.authentication).accessibilityIdentifier("p1.http.auth"); Text(state.cached.isEmpty ? "(empty)" : state.cached).accessibilityIdentifier("p1.http.cache") }
        Section("操作") { Button("Login and persist") { owner.login() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.login"); Button("Reload persisted HTTP state") { owner.reload() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.reload"); Button("Read owner cache") { owner.readCache() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.read-cache"); Button("Hold writer") { owner.startHeldWrite() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.hold"); Button("Cancel held writer") { owner.cancelHeldWrite() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.cancel"); Button("Fail next precommit") { owner.failNextSave = true; owner.status = "precommit failure armed" }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.fail-save"); Button("Request unauthenticated endpoint") { owner.expectedHTTPFailure() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.fail-connect"); Button("Stop writers, then logout") { owner.stopThenLogout() }.buttonStyle(.bordered).accessibilityIdentifier("p1.http.logout") } }.navigationTitle(owner.id.rawValue) }
}
#endif
