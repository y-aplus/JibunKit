#if os(iOS)
import Foundation
import JibunKitCore
import SwiftUI

/// Real Feature composition used by the P2 background diagnostic host. The
/// host enumerates these definitions and invokes onHostLaunch before UI setup.
@MainActor
enum P2BackgroundProbe {
    static let ownerA = ContinuedProcessingFixture(
        id: MiniAppID("p2-background-a"),
        taskIdentifier: "com.jibunkit.app.p2-background-a.export",
        title: "Background export A"
    )
    static let ownerB = ContinuedProcessingFixture(
        id: MiniAppID("p2-background-b"),
        taskIdentifier: "com.jibunkit.app.p2-background-b.export",
        title: "Background export B"
    )

    static let definitions: [MiniAppDefinition] = [ownerA.definition, ownerB.definition]
}

@MainActor
final class ContinuedProcessingFixture: ObservableObject {
    let id: MiniAppID
    let taskIdentifier: String
    let title: String
    @Published private(set) var status = "未開始"
    @Published private(set) var completedUnits: Int64 = 0
    @Published private(set) var generation = 0

    private static let center = MiniAppContinuedProcessingCenter()
    private let tasks: MiniAppContinuedProcessingTasks
    private var worker: Task<Void, Never>?
    private var execution: MiniAppContinuedProcessingExecution?

    init(id: MiniAppID, taskIdentifier: String, title: String) {
        self.id = id
        self.taskIdentifier = taskIdentifier
        self.title = title
        tasks = Self.center.tasks(for: MiniAppContext(id: id))
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id,
            title: title,
            systemImage: "gearshape.2",
            onHostLaunch: { [self] in
                try P2BackgroundServices.register(owner: id)
                try tasks.register(identifier: taskIdentifier) { [weak self] execution in
                    self?.receive(execution)
                }
            }
        ) { [self] _ in
            ContinuedProcessingProbeView(fixture: self)
        }
    }

    func submit(strategy: MiniAppContinuedProcessingStrategy = .queue) {
        do {
            completedUnits = 0
            try tasks.submit(.init(
                identifier: taskIdentifier,
                title: title,
                subtitle: "Waiting to start",
                strategy: strategy
            ))
            status = "受付済み next-generation=\(generation + 1)"
        } catch {
            status = "受付失敗: \(error)"
        }
    }

    func cancel() {
        do { try tasks.cancelPendingRequest(identifier: taskIdentifier) }
        catch { status = "待機取消失敗: \(error)" }
        worker?.cancel()
        worker = nil
        execution?.complete(success: false)
        execution = nil
        status = "Feature取消済み"
    }

    private func receive(_ execution: MiniAppContinuedProcessingExecution) {
        // A new OS launch replaces only this Feature's prior operation. It does
        // not touch the other fixture or process-wide pending requests.
        worker?.cancel()
        self.execution?.complete(success: false)
        self.execution = execution
        generation += 1
        let acceptedGeneration = generation
        execution.onExpiration = { [weak self, weak execution] in
            guard let self, self.execution === execution,
                  self.generation == acceptedGeneration else { return }
            self.status = "OS取消/期限切れ cleanup中"
            self.worker?.cancel()
        }
        status = "OS起動 generation=\(acceptedGeneration)"
        worker = Task { @MainActor [weak self, weak execution] in
            guard let self, let execution else { return }
            for unit in 1...10 {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch {
                    guard self.execution === execution else { return }
                    execution.complete(success: false)
                    self.execution = nil
                    self.status = "取消cleanup完了"
                    return
                }
                guard self.execution === execution,
                      self.generation == acceptedGeneration else { return }
                self.completedUnits = Int64(unit)
                execution.reportProgress(completed: Int64(unit), total: 10)
                execution.updateTitle(self.title, subtitle: "\(unit) / 10")
            }
            guard self.execution === execution else { return }
            execution.complete(success: true)
            self.execution = nil
            self.worker = nil
            self.status = "完了 generation=\(acceptedGeneration)"
        }
    }
}

/// Bundles the existing ordinary BackgroundTasks, durable shared-refresh, and
/// background-URLSession paths into the same real-Feature launch hook. Their
/// behavior remains implemented by the existing Core types.
@MainActor
private enum P2BackgroundServices {
    static let backgroundCenter = MiniAppBackgroundTaskCenter()
    static var sharedCenter: MiniAppSharedRefreshCenter?
    static var urlConnections: [MiniAppID: P2BackgroundURLConnection] = [:]

    static func register(owner: MiniAppID) throws {
        let context = MiniAppContext(id: owner)
        let ordinary = backgroundCenter.tasks(for: context)
        let ordinaryIdentifier = "com.jibunkit.app.\(owner.rawValue).ordinary"
        let kind: MiniAppBackgroundTaskKind = owner == MiniAppID("p2-background-a")
            ? .appRefresh : .processing
        try ordinary.register(identifier: ordinaryIdentifier, kind: kind) {
            $0.complete(success: true)
        }

        let shared = try sharedRefreshCenter().refreshes(for: context)
        try shared.register(identifier: "refresh") { execution in
            _ = execution.complete(success: true)
        }
        _ = sharedRefreshCenter().reconcile()

        let connection = P2BackgroundURLConnection()
        try connection.register(context: context)
        urlConnections[owner] = connection
    }

    private static func sharedRefreshCenter() throws -> MiniAppSharedRefreshCenter {
        if let sharedCenter { return sharedCenter }
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("P2Background", isDirectory: true)
        let center = try MiniAppSharedRefreshCenter(
            identifier: "com.jibunkit.app.p2-background.shared-refresh",
            journalURL: support.appendingPathComponent("shared-refresh.json")
        )
        sharedCenter = center
        return center
    }
}

@MainActor
private final class P2BackgroundURLConnection: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var registration: MiniAppBackgroundURLSessionRegistration?
    private var session: URLSession?
    private var events: MiniAppBackgroundURLSessionEvents?

    func register(context: MiniAppContext) throws {
        registration = try MiniAppBackgroundURLSessionReconnectRegistry.shared.register(
            context: context,
            profile: "diagnostic"
        ) { [weak self] identifier, events in
            guard let self else { throw P2BackgroundConnectionFailure.released }
            self.events = events
            if let session {
                precondition(session.configuration.identifier == identifier)
                return
            }
            session = URLSession(
                configuration: .background(withIdentifier: identifier),
                delegate: self,
                delegateQueue: nil
            )
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let finished = events
            events = nil
            finished?.finish()
        }
    }
}

private enum P2BackgroundConnectionFailure: Error { case released }

private struct ContinuedProcessingProbeView: View {
    @ObservedObject var fixture: ContinuedProcessingFixture

    var body: some View {
        Form {
            Text(fixture.status)
                .accessibilityIdentifier("p2.background.\(fixture.id.rawValue).status")
            ProgressView(value: Double(fixture.completedUnits), total: 10)
            Button("継続処理を開始") { fixture.submit() }
                .accessibilityIdentifier("p2.background.\(fixture.id.rawValue).start")
            Button("即時開始できない場合は失敗") { fixture.submit(strategy: .fail) }
            Button("このFeatureだけ取消") { fixture.cancel() }
                .accessibilityIdentifier("p2.background.\(fixture.id.rawValue).cancel")
        }
    }
}
#endif
