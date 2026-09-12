// Isolated CI host only. Exercises the same Definition/host entry as real Features.
import SwiftUI
import Observation
import JibunKitCore

@MainActor
@Observable
private final class P0Owner {
    let id: MiniAppID
    var generations = 0
    var notifications = 0
    var value = 0
    var ended = 0
    var cleaned = 0
    var failNextStart = false
    private var input: AsyncStream<Int>.Continuation?
    @ObservationIgnored
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        self.generations += 1
        let channel = AsyncStream<Int>.makeStream()
        self.input = channel.continuation
        try runtime.onShutdown { [weak self] in
            self?.input = nil
            self?.cleaned += 1
        }
        let observations = try runtime.makeNotificationObservations()
        try observations.observe(name: P0ALifetimeProbe.event, extract: { _ in true }) { [weak self] _ in
            self?.notifications += 1
        }
        try runtime.start { [weak self] in
            for await value in channel.stream { await self?.record(value) }
            await self?.didEnd()
        }
        if self.failNextStart {
            self.failNextStart = false
            throw ProbeFailure.requested
        }
    }

    init(_ id: String) { self.id = MiniAppID(id) }
    func send(_ value: Int) { input?.yield(value) }
    private func record(_ value: Int) { self.value = value }
    private func didEnd() { ended += 1 }

    var summary: String {
        let phase: String
        switch lifetime.state {
        case .stopped: phase = "stopped"
        case .starting: phase = "starting"
        case .running: phase = "running"
        case .stopping: phase = "stopping"
        case .failed: phase = "failed"
        }
        return "g=\(generations),n=\(notifications),value=\(value),ended=\(ended),cleaned=\(cleaned),state=\(phase)"
    }
    private enum ProbeFailure: Error { case requested }
}

@MainActor
enum P0ALifetimeProbe {
    static let event = Notification.Name("JibunKit.P0A.lifetime")
    private static let a = P0Owner("p0-a")
    private static let b = P0Owner("p0-b")
    static let definitions: [MiniAppDefinition] = [a, b].map { owner in
        MiniAppDefinition(id: owner.id, title: owner.id == a.id ? "P0 A" : "P0 B",
                          systemImage: "play.circle", lifetime: owner.lifetime) { _ in
            ProbeView()
        }
    }

    private struct ProbeView: View {
        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    Text(a.summary).accessibilityIdentifier("p0.summary.a")
                    Text(b.summary).accessibilityIdentifier("p0.summary.b")
                    Button("Broadcast") { NotificationCenter.default.post(name: event, object: nil) }
                        .accessibilityIdentifier("p0.broadcast")
                    Button("Send A") { a.send(11) }.accessibilityIdentifier("p0.send.a")
                    Button("Send B") { b.send(22) }.accessibilityIdentifier("p0.send.b")
                    Button("Stop A") { Task { await a.lifetime.stop() } }
                        .accessibilityIdentifier("p0.stop.a")
                    Button("Fail next A start") { a.failNextStart = true }
                        .accessibilityIdentifier("p0.fail.a")
                    Button("Start A") { Task { try? await a.lifetime.start() } }
                        .accessibilityIdentifier("p0.start.a")
                }.padding()
            }
        }
    }
}
