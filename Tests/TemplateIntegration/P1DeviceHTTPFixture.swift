// Diagnostic-only loopback HTTP; no interception or fabricated auth callback.
#if os(iOS)
import Foundation
import Network

@MainActor
final class P1DeviceHTTPFixture {
    static let shared = P1DeviceHTTPFixture()
    private let queue = DispatchQueue(label: "JibunKit.P1DeviceHTTPFixture")
    private let port: UInt16
    private let headerTimeout: Duration
    private let gateTimeout: Duration
    private var listener: NWListener?
    private var readyURL: URL?
    private var startup: CheckedContinuation<URL, Error>?
    private var startupDeadline: Task<Void, Never>?
    private var startTask: Task<URL, Error>?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var gates: [String: Gate] = [:]
    var liveConnectionCount: Int { connections.count }
    var waitingRequestCount: Int { gates.values.reduce(0) { $0 + $1.waiters.count } }

    // Tests request an ephemeral loopback port and short expiration periods.
    init(port: UInt16 = 8766, headerTimeout: Duration = .seconds(5), gateTimeout: Duration = .seconds(20)) {
        self.port = port
        self.headerTimeout = headerTimeout
        self.gateTimeout = gateTimeout
    }

    func start() async throws -> URL {
        if let readyURL { return readyURL }
        if let startTask { return try await startTask.value }
        let task = Task { @MainActor in try await self.listen() }
        startTask = task
        do {
            let url = try await task.value
            startTask = nil
            return url
        } catch {
            startTask = nil
            throw error
        }
    }

    private func listen() async throws -> URL {
        let parameters = NWParameters.tcp
        let port = NWEndpoint.Port(rawValue: port)!
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port)
        // The endpoint already specifies both address and port. Passing a fixed
        // `on:` port as well selects the incompatible create-with-port path.
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self, weak listener] network in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { network.cancel(); return }
                self.accept(network)
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else { self.stop(); return }
                    let url = URL(string: "http://127.0.0.1:\(port.rawValue)")!
                    self.readyURL = url
                    self.settleStartup(.success(url))
                case .failed(let error): self.stop(error: error)
                case .cancelled: self.stop()
                default: break
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            startupDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.stop(error: Failure.startTimedOut)
            }
            listener.start(queue: queue)
        }
    }

    private func settleStartup(_ result: Result<URL, Error>) {
        startupDeadline?.cancel()
        startupDeadline = nil
        let continuation = startup
        startup = nil
        continuation?.resume(with: result)
    }

    func stop() { stop(error: Failure.unavailable) }

    private func stop(error: Error) {
        let previous = listener
        listener = nil
        readyURL = nil
        settleStartup(.failure(error))
        previous?.cancel()
        for gate in gates.values { gate.expiration?.cancel() }
        gates.removeAll()
        for connection in Array(connections.values) { finish(connection) }
    }

    private func accept(_ network: NWConnection) {
        guard connections.count < 64 else { network.cancel(); return }
        let connection = Connection(network)
        connections[connection.id] = connection
        network.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection else { return }
                switch state {
                case .failed, .cancelled: self.finish(connection)
                default: break
                }
            }
        }
        network.start(queue: queue)
        connection.deadline = Task { @MainActor [weak self, weak connection] in
            guard let self else { return }
            do { try await Task.sleep(for: self.headerTimeout) } catch { return }
            guard let connection else { return }
            self.respond(connection, 408)
        }
        receive(connection)
    }

    private func receive(_ connection: Connection) {
        connection.network.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection, self.connections[connection.id] != nil, !connection.responding else { return }
                if error != nil { self.finish(connection); return }
                connection.buffer.append(data ?? Data())
                guard connection.buffer.count <= 16_384 else { self.respond(connection, 431); return }
                if let end = connection.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    connection.deadline?.cancel()
                    self.handle(connection, header: connection.buffer[..<end.lowerBound])
                } else if complete {
                    self.respond(connection, 400)
                } else {
                    self.receive(connection)
                }
            }
        }
    }

    private func handle(_ connection: Connection, header: Data) {
        guard let text = String(data: header, encoding: .utf8) else { respond(connection, 400); return }
        let rows = text.components(separatedBy: "\r\n")
        let request = rows[0].split(separator: " ")
        guard request.count == 3, request[0] == "GET", request[1].count <= 256,
              request[2] == "HTTP/1.1" else { respond(connection, 400); return }
        var headers: [String: String] = [:]
        for row in rows.dropFirst() {
            let parts = row.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { respond(connection, 400); return }
            let key = parts[0].lowercased()
            guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  headers[key] == nil else { respond(connection, 400); return }
            headers[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, headers["content-length"] == nil || headers["content-length"] == "0" else {
            respond(connection, 400); return
        }
        route(String(request[1]), headers: headers, connection: connection)
    }

    private func route(_ path: String, headers: [String: String], connection: Connection) {
        switch path {
        case "/auth":
            if let authorization = headers["authorization"] { respond(connection, 200, authorization) }
            else { respond(connection, 401, headers: ["WWW-Authenticate: Basic realm=\"same\""]) }
        case "/redirect": respond(connection, 302, headers: ["Location: /echo"])
        case "/echo": respond(connection, 200, headers["cookie"] ?? "")
        case "/set", "/set-persistent":
            let value = headers["x-fixture-owner"] ?? "missing"
            respond(connection, 200, value, headers: ["Set-Cookie: account=\(value); Path=/" + (path == "/set-persistent" ? "; Max-Age=3600" : "")])
        case "/logout": respond(connection, 200, headers: ["Set-Cookie: account=; Max-Age=0; Path=/"])
        case "/complete":
            respond(connection, 200, "<a href=\"jibunkit-auth-probe://callback?code=local\">Return to App</a>", headers: ["Content-Type: text/html; charset=utf-8"])
        case "/hold":
            respond(connection, 200, "<title>Hold for cancellation</title><p>Cancel this authentication session.</p>", headers: ["Content-Type: text/html; charset=utf-8"])
        default:
            if path.hasPrefix("/cache/") {
                respond(connection, 200, headers["x-fixture-owner"] ?? "missing", headers: ["Cache-Control: max-age=3600"])
            } else { routeGate(path, connection: connection) }
        }
    }

    private func routeGate(_ path: String, connection: Connection) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[1].count <= 128,
              ["hold", "await-start", "release"].contains(String(parts[0])) else { respond(connection, 404); return }
        let token = String(parts[1])
        let gate: Gate
        if let existing = gates[token] { gate = existing }
        else {
            guard gates.count < 32 else { respond(connection, 429); return }
            gate = Gate()
            gates[token] = gate
            gate.expiration = Task { @MainActor [weak self, weak gate] in
                guard let self else { return }
                do { try await Task.sleep(for: self.gateTimeout) } catch { return }
                guard let gate, self.gates[token] === gate else { return }
                if let hold = gate.hold { self.respond(hold, 504) }
                for waiter in gate.waiters { self.respond(waiter, 504) }
                self.gates.removeValue(forKey: token)
            }
        }
        switch parts[0] {
        case "hold":
            guard !gate.started else { respond(connection, 409); return }
            gate.started = true
            for waiter in gate.waiters { respond(waiter, 200) }
            gate.waiters.removeAll()
            if gate.released { completeHold(connection) }
            else { gate.hold = connection }
        case "await-start":
            if gate.started { respond(connection, 200) }
            else if gate.waiters.count < 16 { gate.waiters.append(connection) }
            else { respond(connection, 429) }
        case "release":
            gate.released = true
            if let hold = gate.hold { gate.hold = nil; completeHold(hold) }
            respond(connection, 200)
        default: break
        }
    }

    private func completeHold(_ connection: Connection) {
        respond(connection, 200, headers: ["Set-Cookie: account=late-response; Path=/; Max-Age=3600"])
    }

    private func respond(_ connection: Connection, _ status: Int, _ body: String = "", headers: [String] = []) {
        guard connections[connection.id] != nil, !connection.responding else { return }
        connection.responding = true
        connection.deadline?.cancel()
        let bytes = Data(body.utf8)
        let policy = headers.contains { $0.lowercased().hasPrefix("cache-control:") } ? [] : ["Cache-Control: no-store"]
        let type = headers.contains { $0.lowercased().hasPrefix("content-type:") } ? [] : ["Content-Type: text/plain; charset=utf-8"]
        let response = (["HTTP/1.1 \(status) \(status == 200 ? "OK" : "Response")", "Content-Length: \(bytes.count)", "Connection: close"] + policy + type + headers + ["", ""]).joined(separator: "\r\n")
        connection.network.send(content: Data(response.utf8) + bytes, completion: .contentProcessed { [weak self, weak connection] _ in
            Task { @MainActor in
                guard let self, let connection else { return }
                self.finish(connection)
            }
        })
        // Even a client that never reads cannot retain a response indefinitely.
        connection.deadline = Task { @MainActor [weak self, weak connection] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, let connection else { return }
            self.finish(connection)
        }
    }

    private func finish(_ connection: Connection) {
        connections.removeValue(forKey: connection.id)
        connection.deadline?.cancel()
        connection.network.cancel()
    }

    @MainActor private final class Connection {
        let network: NWConnection
        var id: ObjectIdentifier { ObjectIdentifier(network) }
        var buffer = Data()
        var responding = false
        var deadline: Task<Void, Never>?
        init(_ network: NWConnection) { self.network = network }
    }
    @MainActor private final class Gate {
        var started = false
        var released = false
        var hold: Connection?
        var waiters: [Connection] = []
        var expiration: Task<Void, Never>?
    }
    enum Failure: Error { case unavailable, startTimedOut }
}
#endif
