// Diagnostic-host-only. iOS SDK: Network.framework NWListener/NWConnection.
#if os(iOS)
import Foundation
import Network

@MainActor final class P1DeviceHTTPFixture {
    static let shared = P1DeviceHTTPFixture(); static let url = URL(string: "http://127.0.0.1:8766")!
    private let queue = DispatchQueue(label: "JibunKit.P1DeviceHTTPFixture")
    private var listener: NWListener?, startTask: Task<URL, Error>?
    private var gates: [String: Gate] = [:], live: Set<ObjectIdentifier> = []
    private init() {}
    func start() async throws -> URL {
        if listener != nil { return Self.url }; if let startTask { return try await startTask.value }
        let task = Task { @MainActor [weak self] () throws -> URL in
            guard let self else { throw Failure.unavailable }
            let p = NWParameters.tcp
            let port = NWEndpoint.Port(rawValue: 8766)!
            p.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port)
            let listener = try NWListener(using: p, on: port)
            listener.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.accept(c) } }
            try await self.awaitReady(listener)
            self.listener = listener; return Self.url
        }
        startTask = task
        do { let url = try await task.value; startTask = nil; return url }
        catch { startTask = nil; listener?.cancel(); listener = nil; throw error }
    }
    private func awaitReady(_ listener: NWListener) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                var done = false
                listener.stateUpdateHandler = { state in guard !done else { return }; switch state {
                case .ready: done = true; c.resume()
                case .failed(let e): done = true; c.resume(throwing: e)
                case .cancelled: done = true; c.resume(throwing: Failure.unavailable)
                default: break } }
                listener.start(queue: self.queue)
            }}
            group.addTask { try await Task.sleep(for: .seconds(5)); throw Failure.startTimedOut }
            defer { group.cancelAll() }
            _ = try await group.next()!
        }
    }
    private func accept(_ c: NWConnection) {
        guard live.count < 64 else { return close(c, 503) }
        live.insert(ObjectIdentifier(c)); c.start(queue: queue); receive(c, Data(), deadline: Task { try? await Task.sleep(for: .seconds(5)) })
    }
    private func receive(_ c: NWConnection, _ buffer: Data, deadline: Task<Void, Never>) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in Task { @MainActor in
            guard let self else { c.cancel(); return }; guard error == nil, let data else { return self.finish(c) }
            let all = buffer + data; guard all.count <= 16_384 else { deadline.cancel(); return self.close(c, 431) }
            if all.range(of: Data("\r\n\r\n".utf8)) == nil { if complete { deadline.cancel(); self.close(c, 400) } else { self.receive(c, all, deadline: deadline) }; return }
            deadline.cancel(); self.handle(c, all)
        }}
    }
    private func handle(_ c: NWConnection, _ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return close(c, 400) }
        let rows = text.components(separatedBy: "\r\n"); guard let first = rows.first else { return close(c, 400) }
        let request = first.split(separator: " "); guard request.count == 3, request[0] == "GET", request[1].count <= 256 else { return close(c, 400) }
        var headers: [String: String] = [:]
        for row in rows.dropFirst() where !row.isEmpty { let p = row.split(separator: ":", maxSplits: 1); guard p.count == 2 else { return close(c, 400) }; let k = p[0].lowercased(); guard headers[k] == nil else { return close(c, 400) }; headers[k] = p[1].trimmingCharacters(in: .whitespaces) }
        route(String(request[1]), headers, c)
    }
    private func route(_ path: String, _ h: [String:String], _ c: NWConnection) {
        if path == "/auth" { guard let a = h["authorization"] else { return close(c, 401, headers:["WWW-Authenticate: Basic realm=\"same\""]) }; return close(c, 200, a) }
        if path == "/redirect" { return close(c, 302, headers:["Location: /echo"]) }; if path == "/echo" { return close(c, 200, h["cookie"] ?? "") }
        if path.hasPrefix("/set") { let v=h["x-fixture-owner"] ?? "missing"; return close(c, 200, v, headers:["Set-Cookie: account=\(v); Path=/" + (path == "/set-persistent" ? "; Max-Age=3600" : "")]) }
        if path == "/logout" { return close(c, 200, headers:["Set-Cookie: account=; Max-Age=0; Path=/"]) }
        if path.hasPrefix("/cache/") { return close(c, 200, h["x-fixture-owner"] ?? "missing", headers:["Cache-Control: max-age=3600"]) }
        if path == "/complete" { return close(c, 200, "<a href=\"jibunkit-auth-probe://callback?code=local\">Return to App</a>", headers:["Content-Type: text/html; charset=utf-8"]) }
        if path == "/hold" { return close(c, 200, "<title>Hold for cancellation</title><p>Cancel this authentication session.</p>", headers:["Content-Type: text/html; charset=utf-8"]) }
        let p=path.split(separator:"/", omittingEmptySubsequences:true); guard p.count==2, p[1].count <= 128 else { return close(c,404) }; let op=String(p[0]), token=String(p[1]); let gate=gates[token] ?? Gate(); if gates[token] == nil { guard gates.count < 32 else { return close(c,429) }; gates[token]=gate; gate.reclaim = Task { @MainActor [weak self, weak gate] in try? await Task.sleep(for:.seconds(20)); guard !Task.isCancelled, let self, let gate, gate.hold == nil else{return}; self.gates.removeValue(forKey:token) } }
        switch op {
        case "hold": guard gate.hold == nil else { return close(c,409) }; gate.started=true; gate.hold=c; gate.waiters.forEach { close($0,200) }; gate.waiters=[]; gate.timeout?.cancel(); gate.timeout=Task { @MainActor [weak self, weak gate] in do { try await Task.sleep(for:.seconds(20)) } catch { return }; guard let self, let gate, gate.hold === c else{return}; gate.hold=nil; self.close(c,504); self.removeGate(token,gate) }
        case "await-start": if gate.started { close(c,200) } else if gate.waiters.count < 16 { gate.waiters.append(c) } else { close(c,429) }
        case "release": close(c,200); gate.timeout?.cancel(); if let hold=gate.hold { gate.hold=nil; close(hold,200,headers:["Set-Cookie: account=late-response; Path=/; Max-Age=3600"]) }; gate.waiters.forEach { close($0,504) }; gate.waiters=[]; removeGate(token,gate)
        default: close(c,404) }
    }
    private func removeGate(_ token:String,_ gate:Gate) { gate.timeout?.cancel(); gate.reclaim?.cancel(); gates.removeValue(forKey:token) }
    private func close(_ c:NWConnection,_ status:Int=200,_ body:String="",headers:[String]=[]) { let body=Data(body.utf8); let policy=headers.contains{$0.lowercased().hasPrefix("cache-control:")} ? [] : ["Cache-Control: no-store"]; let type=headers.contains{$0.lowercased().hasPrefix("content-type:")} ? [] : ["Content-Type: text/plain; charset=utf-8"]; let response=(["HTTP/1.1 \(status) \(status==200 ? "OK":"Error")","Content-Length: \(body.count)","Connection: close"]+policy+type+headers+["",""]).joined(separator:"\r\n"); c.send(content:Data(response.utf8)+body,completion:.contentProcessed{_ in c.cancel()}); finish(c) }
    private func finish(_ c:NWConnection) { live.remove(ObjectIdentifier(c)); c.cancel() }
    private final class Gate { var started=false; var hold:NWConnection?; var waiters:[NWConnection]=[]; var timeout:Task<Void,Never>?; var reclaim:Task<Void,Never>? }
    enum Failure:Error { case unavailable,startTimedOut }
}
#endif
