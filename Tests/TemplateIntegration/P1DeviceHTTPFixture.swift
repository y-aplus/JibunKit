// Diagnostic-host-only loopback fixture. Requires iOS Network.framework.
#if os(iOS)
import Foundation
import Network

@MainActor
final class P1DeviceHTTPFixture {
    static let shared = P1DeviceHTTPFixture()
    private static let port: UInt16 = 8766
    private var listener: NWListener?
    private var starting: Task<URL, Error>?
    private var gates: [String: Gate] = [:]
    private let queue = DispatchQueue(label: "JibunKit.P1DeviceHTTPFixture")
    private init() {}

    /// CI's externally started fixture wins. Device diagnostics bind only 127.0.0.1:8766.
    func start() async throws -> URL {
        if let raw = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"], let port = UInt16(raw) {
            return URL(string: "http://127.0.0.1:\(port)")!
        }
        if listener != nil { return Self.url }
        if let starting { return try await starting.value }
        let task = Task { @MainActor [weak self] () throws -> URL in
            guard let self else { throw Failure.unavailable }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                listener.stateUpdateHandler = { state in
                    switch state { case .ready: continuation.resume()
                    case .failed(let error): continuation.resume(throwing: error)
                    case .cancelled: continuation.resume(throwing: Failure.unavailable)
                    default: break }
                }
                listener.start(queue: self.queue)
            }
            self.listener = listener
            return Self.url
        }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private static var url: URL { URL(string: "http://127.0.0.1:\(port)")! }
    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }
    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard error == nil, let data else { self.close(connection, status: 400); return }
                let combined = buffer + data
                guard combined.count <= 16_384 else { return self.close(connection, status: 431) }
                if combined.range(of: Data("\r\n\r\n".utf8)) == nil { return self.receiveRequest(connection, buffer: combined) }
                self.handle(connection, data: combined)
            }
        }
    }
    private func handle(_ connection: NWConnection, data: Data) {
        guard let text = String(data: data, encoding: .utf8), let line = text.split(separator: "\r\n").first else { return close(connection, status: 400) }
        let parts = line.split(separator: " "); guard parts.count == 3, parts[0] == "GET", parts[1].count <= 256 else { return close(connection, status: 400) }
        let path = String(parts[1]); let headers = Dictionary(uniqueKeysWithValues: text.split(separator: "\r\n").dropFirst().prefix(64).compactMap { row -> (String, String)? in let pair = row.split(separator: ":", maxSplits: 1); return pair.count == 2 ? (pair[0].lowercased(), pair[1].trimmingCharacters(in: .whitespaces)) : nil })
        route(path, headers: headers, connection: connection)
    }
    private func route(_ path: String, headers: [String: String], connection: NWConnection) {
        if path == "/auth" { guard let authorization = headers["authorization"] else { return close(connection, status: 401, headers: ["WWW-Authenticate: Basic realm=\"same\""]) }; return close(connection, body: authorization) }
        if path == "/redirect" { return close(connection, status: 302, headers: ["Location: /echo"]) }
        if path == "/echo" { return close(connection, body: headers["cookie"] ?? "") }
        if path.hasPrefix("/set") { let owner = headers["x-fixture-owner"] ?? "missing"; let persistent = path == "/set-persistent" ? "; Max-Age=3600" : ""; return close(connection, body: owner, headers: ["Set-Cookie: account=\(owner); Path=/\(persistent)"]) }
        if path == "/logout" { return close(connection, body: "", headers: ["Set-Cookie: account=; Max-Age=0; Path=/"]) }
        if path.hasPrefix("/cache/") { return close(connection, body: headers["x-fixture-owner"] ?? "missing", headers: ["Cache-Control: max-age=3600"]) }
        if path == "/complete" { return close(connection, body: "<a href=\"jibunkit-auth-probe://callback?code=local\">Return to App</a>", headers: ["Content-Type: text/html; charset=utf-8"]) }
        if path == "/hold" { return close(connection, body: "<title>Hold for cancellation</title><p>Cancel this authentication session.</p>", headers: ["Content-Type: text/html; charset=utf-8"]) }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[1].count <= 128 else { return close(connection, status: 404) }
        let operation = String(components[0]), token = String(components[1])
        switch operation {
        case "hold":
            guard gates.count < 32 || gates[token] != nil else { return close(connection, status: 429) }
            let gate = gates[token] ?? Gate(); gates[token] = gate; gate.hold = connection; gate.started = true
            gate.timeout = Task { @MainActor [weak self, weak gate] in try? await Task.sleep(for: .seconds(20)); guard let self, let gate, gate.hold === connection else { return }; self.close(connection, status: 504); self.gates.removeValue(forKey: token) }
        case "await-start": close(connection, status: gates[token]?.started == true ? 200 : 504)
        case "release":
            let gate = gates.removeValue(forKey: token); gate?.timeout?.cancel(); close(connection, status: 200)
            if let held = gate?.hold { close(held, status: 200, headers: ["Set-Cookie: account=late-response; Path=/; Max-Age=3600"]) }
        default: close(connection, status: 404)
        }
    }
    private func close(_ connection: NWConnection, status: Int = 200, body: String = "", headers: [String] = []) {
        let payload = Data(body.utf8)
        let response = (["HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")", "Content-Length: \(payload.count)", "Connection: close", "Cache-Control: no-store"] + headers + ["", ""]).joined(separator: "\r\n")
        connection.send(content: Data(response.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
    }
    private final class Gate { var started = false; var hold: NWConnection?; var timeout: Task<Void, Never>? }
    enum Failure: Error { case unavailable }
}
#endif
