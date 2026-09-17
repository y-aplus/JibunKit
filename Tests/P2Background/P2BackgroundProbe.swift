#if os(iOS)
import Foundation
import JibunKitCore
import SwiftUI

@MainActor
enum P2BackgroundProbe {
    static let center = MiniAppContinuedProcessingCenter()
    static let ownerA = P2BackgroundFeature(
        id: MiniAppID("p2-background-a"), title: "Background A",
        continued: center.tasks(for: MiniAppContext(id: MiniAppID("p2-background-a"))))
    static let ownerB = P2BackgroundFeature(
        id: MiniAppID("p2-background-b"), title: "Background B",
        continued: center.tasks(for: MiniAppContext(id: MiniAppID("p2-background-b"))))
    static let definitions: [MiniAppDefinition] = [ownerA.definition, ownerB.definition]
}

@MainActor
final class P2BackgroundFeature: ObservableObject {
    typealias Work = @MainActor @Sendable (
        _ progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws -> Void

    let id: MiniAppID
    let title: String
    let continuedBaseIdentifier: String
    @Published private(set) var status = "未開始"
    @Published private(set) var progress: Int64 = 0
    @Published private(set) var resultCount = 0
    @Published private(set) var generation = 0
    @Published private(set) var ordinaryStatus = "未受付"
    @Published private(set) var sharedStatus = "未受付"
    @Published private(set) var transferStatus = "未開始"

    private let continued: MiniAppContinuedProcessingTasks
    private let work: Work
    private var runtime: MiniAppRuntime?
    private var receipt: MiniAppContinuedProcessingReceipt?
    private var execution: MiniAppContinuedProcessingExecution?
    private var worker: Task<Void, Never>?

    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.connect(runtime)
    }

    init(id: MiniAppID, title: String, continued: MiniAppContinuedProcessingTasks,
         work: @escaping Work = P2BackgroundFeature.productionWork) {
        self.id = id
        self.title = title
        self.continued = continued
        self.work = work
        continuedBaseIdentifier = "com.jibunkit.app.\(id.rawValue).export"
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: title, systemImage: "gearshape.2", lifetime: lifetime,
            onUnregister: { [weak self] in
                guard let self else { return }
                await self.disable()
                P2BackgroundServices.unregister(owner: self.id)
            },
            onHostLaunch: { [self] in try P2BackgroundServices.register(feature: self) }
        ) { [self] _ in P2BackgroundProbeView(feature: self) }
    }

    func submitContinued(strategy: MiniAppContinuedProcessingStrategy = .queue) {
        guard let runtime, !runtime.isClosed, worker == nil, receipt == nil else {
            status = "受付拒否: Feature停止中または仕事実行中"
            return
        }
        let request = MiniAppContinuedProcessingRequest(
            baseIdentifier: continuedBaseIdentifier,
            title: title + " export", subtitle: "Waiting to start", strategy: strategy)
        do {
            let submitted = try continued.submit(request) { [weak self, weak runtime] execution in
                self?.receive(execution, runtime: runtime)
            }
            if execution == nil {
                receipt = submitted
                status = "受付済み job=\(request.jobIdentifier.uuidString.prefix(8))"
            }
        } catch { status = "受付失敗: \(error)" }
    }

    func cancelContinued() async {
        if let receipt { try? continued.cancelPendingRequest(identifier: receipt.identifier) }
        await cancelWorkerAndJoin(success: false, reason: "Feature取消済み")
        receipt = nil
    }

    func submitOrdinary() { ordinaryStatus = P2BackgroundServices.submitOrdinary(owner: id) }
    func submitSharedRefresh() { sharedStatus = P2BackgroundServices.submitShared(owner: id) }
    func refreshSharedJournalStatus() { sharedStatus = P2BackgroundServices.sharedStatus(owner: id) }
    func startDownload(urlText: String) {
        transferStatus = P2BackgroundServices.startDownload(owner: id, urlText: urlText)
    }

    fileprivate func receiveOrdinary(_ execution: MiniAppBackgroundTaskExecution) {
        ordinaryStatus = "OS起動・仕事中"
        Task { @MainActor [weak self, weak execution] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let execution else { return }
            let success = !execution.isExpired
            execution.complete(success: success)
            self.ordinaryStatus = success ? "OS仕事完了" : "expiration cleanup完了"
        }
    }

    fileprivate func receiveShared(_ execution: MiniAppSharedRefreshExecution) {
        sharedStatus = execution.request.isRecovery ? "cold recovery仕事中" : "共有refresh仕事中"
        Task { @MainActor [weak self, weak execution] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let execution else { return }
            let success = !execution.isExpired
            _ = execution.complete(success: success)
            self.sharedStatus = success ? "共有仕事完了" : "共有cleanup完了・再試行保持"
        }
    }

    fileprivate func setTransferStatus(_ value: String) { transferStatus = value }
    fileprivate func setSharedStatus(_ value: String) { sharedStatus = value }

    private func connect(_ runtime: MiniAppRuntime) throws {
        try runtime.onShutdownAsync { [weak self, weak runtime] in
            await self?.shutdown(runtime: runtime)
        }
        self.runtime = runtime
        generation += 1
        status = "利用可能 generation=\(generation)"
    }

    private func receive(_ execution: MiniAppContinuedProcessingExecution, runtime expected: MiniAppRuntime?) {
        guard let runtime, runtime === expected, !runtime.isClosed, worker == nil else {
            execution.complete(success: false)
            status = "遅着OS起動を拒否"
            return
        }
        self.execution = execution
        receipt = nil
        generation += 1
        let acceptedGeneration = generation
        execution.onExpiration = { [weak self, weak execution] in
            guard let self, self.execution === execution else { return }
            Task { @MainActor in
                await self.cancelWorkerAndJoin(success: false, reason: "OS取消/期限切れ cleanup完了")
            }
        }
        status = "OS起動 generation=\(acceptedGeneration)"
        worker = Task { @MainActor [weak self, weak execution, work] in
            guard let self, let execution else { return }
            do {
                try await work { [weak self, weak execution] completed, total in
                    guard let self, let execution, self.execution === execution,
                          self.generation == acceptedGeneration else { return }
                    self.progress = completed
                    execution.reportProgress(completed: completed, total: total)
                    execution.updateTitle(self.title, subtitle: "\(completed) / \(total)")
                }
                guard self.execution === execution, self.generation == acceptedGeneration else {
                    execution.complete(success: false)
                    return
                }
                execution.complete(success: true)
                self.execution = nil
                self.worker = nil
                self.resultCount += 1
                self.status = "完了 generation=\(acceptedGeneration)"
            } catch {
                guard self.execution === execution else { return }
                execution.complete(success: false)
                self.execution = nil
                self.worker = nil
                self.status = "cleanup完了: \(error)"
            }
        }
    }

    private func shutdown(runtime expected: MiniAppRuntime?) async {
        guard runtime === expected else { return }
        runtime = nil // close Feature admission before native cancellation/cleanup
        if let receipt { try? continued.cancelPendingRequest(identifier: receipt.identifier) }
        receipt = nil
        await cancelWorkerAndJoin(success: false, reason: "停止cleanup完了")
    }

    private func cancelWorkerAndJoin(success: Bool, reason: String) async {
        let ownedWorker = worker
        ownedWorker?.cancel()
        await ownedWorker?.value
        execution?.complete(success: success)
        execution = nil
        worker = nil
        status = reason
    }

    private func disable() async {
        lifetime.setStartAllowed(false)
        await lifetime.stop()
    }

    private static func productionWork(
        progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws {
        for unit in 1...60 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            progress(Int64(unit), 60)
        }
    }
}

@MainActor
private enum P2BackgroundServices {
    static let backgroundCenter = MiniAppBackgroundTaskCenter()
    static var sharedCenter: MiniAppSharedRefreshCenter?
    static var ordinary: [MiniAppID: MiniAppBackgroundTasks] = [:]
    static var shared: [MiniAppID: MiniAppSharedRefresh] = [:]
    static var urlConnections: [MiniAppID: P2BackgroundURLConnection] = [:]
    static var registeredOwners: Set<MiniAppID> = []

    static func register(feature: P2BackgroundFeature) throws {
        let context = MiniAppContext(id: feature.id)
        let ordinaryTasks = backgroundCenter.tasks(for: context)
        let ordinaryIdentifier = "com.jibunkit.app.\(feature.id.rawValue).ordinary"
        let kind: MiniAppBackgroundTaskKind = feature.id == MiniAppID("p2-background-a")
            ? .appRefresh : .processing
        try ordinaryTasks.register(identifier: ordinaryIdentifier, kind: kind) { [weak feature] in
            guard let feature, registeredOwners.contains(feature.id) else {
                $0.complete(success: false); return
            }
            feature.receiveOrdinary($0)
        }
        ordinary[feature.id] = ordinaryTasks

        let sharedCenter = try sharedRefreshCenter()
        let sharedTasks = sharedCenter.refreshes(for: context)
        try sharedTasks.register(identifier: "refresh") { [weak feature] in
            guard let feature, registeredOwners.contains(feature.id) else {
                _ = $0.complete(success: false); return
            }
            feature.receiveShared($0)
        }
        shared[feature.id] = sharedTasks
        registeredOwners.insert(feature.id)
        _ = sharedCenter.reconcile()
        feature.setSharedStatus(sharedStatus(owner: feature.id))

        let connection = P2BackgroundURLConnection(owner: feature.id) { [weak feature] in
            feature?.setTransferStatus($0)
        }
        do { try connection.register(context: context) }
        catch {
            registeredOwners.remove(feature.id)
            sharedTasks.unregister(identifier: "refresh")
            shared.removeValue(forKey: feature.id)
            ordinary.removeValue(forKey: feature.id)
            throw error
        }
        urlConnections[feature.id] = connection
    }

    static func submitOrdinary(owner: MiniAppID) -> String {
        do {
            try ordinary[owner]?.submit(.init(
                identifier: "com.jibunkit.app.\(owner.rawValue).ordinary",
                requiresNetworkConnectivity: owner == MiniAppID("p2-background-b")))
            return "受付済み（OS起動待ち）"
        } catch { return "受付失敗: \(error)" }
    }

    static func unregister(owner: MiniAppID) {
        registeredOwners.remove(owner)
        ordinary[owner]?.cancelAllPendingRequests()
        ordinary.removeValue(forKey: owner)
        if let sharedTasks = shared.removeValue(forKey: owner) {
            try? sharedTasks.cancelAllPendingRequests()
            sharedTasks.unregister(identifier: "refresh")
            if let sharedCenter { _ = sharedCenter.reconcile() }
        }
        // Retain the delegate until URLSession reports that all events finished;
        // unregistering a Feature must not release the host completion early.
        urlConnections[owner]?.cancel()
    }

    static func submitShared(owner: MiniAppID) -> String {
        do {
            let receipt = try shared[owner]?.submit(identifier: "refresh")
            let generation = receipt.map { String($0.generation.uuidString.prefix(8)) } ?? "missing"
            return "journal受付 generation=\(generation)"
        } catch { return "journal受付失敗: \(error)" }
    }

    static func sharedStatus(owner: MiniAppID) -> String {
        let pending = shared[owner]?.pendingRequests ?? []
        return pending.isEmpty ? "journal空" : pending.map {
            "\($0.generation.uuidString.prefix(8)):recovery=\($0.isRecovery)"
        }.joined(separator: ",")
    }

    static func startDownload(owner: MiniAppID, urlText: String) -> String {
        guard let url = URL(string: urlText), let connection = urlConnections[owner] else {
            return "URL/connection不正"
        }
        return connection.start(url: url)
    }

    private static func sharedRefreshCenter() throws -> MiniAppSharedRefreshCenter {
        if let sharedCenter { return sharedCenter }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("P2Background", isDirectory: true)
        let center = try MiniAppSharedRefreshCenter(
            identifier: "com.jibunkit.app.p2-background.shared-refresh",
            journalURL: support.appendingPathComponent("shared-refresh.json"))
        sharedCenter = center
        return center
    }
}

@MainActor
private final class P2BackgroundURLConnection: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let owner: MiniAppID
    let destinationDirectory: URL
    private let status: @MainActor (String) -> Void
    private var registration: MiniAppBackgroundURLSessionRegistration?
    private var session: URLSession?
    private var events: MiniAppBackgroundURLSessionEvents?
    private var downloadedLocations: [Int: URL] = [:]
    private var completedEvents = 0

    init(owner: MiniAppID, status: @escaping @MainActor (String) -> Void) {
        self.owner = owner
        self.status = status
        destinationDirectory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask)[0]
            .appendingPathComponent("P2Background/Downloads/\(owner.storageNamespace)", isDirectory: true)
    }

    func register(context: MiniAppContext) throws {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        registration = try MiniAppBackgroundURLSessionReconnectRegistry.shared.register(
            context: context, profile: "diagnostic") { [weak self] identifier, events in
                guard let self else { throw P2BackgroundConnectionFailure.released }
                self.events = events
                self.ensureSession(identifier: identifier)
                self.status("OS callback再接続・delegate event待ち")
            }
    }

    func start(url: URL) -> String {
        guard let identifier = registration?.identifier else { return "未登録" }
        ensureSession(identifier: identifier)
        let task = session!.downloadTask(with: url)
        task.resume()
        return "download開始 task=\(task.taskIdentifier) owner=\(owner.rawValue)"
    }

    func cancel() {
        registration?.cancel()
        registration = nil
        session?.invalidateAndCancel()
    }

    private func ensureSession(identifier: String) {
        if let session { precondition(session.configuration.identifier == identifier); return }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        let destination = destinationDirectory.appendingPathComponent(
            "\(downloadTask.taskIdentifier)-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in downloadedLocations[downloadTask.taskIdentifier] = destination }
        } catch { Task { @MainActor in status("保存失敗: \(error)") } }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               didCompleteWithError error: Error?) {
        Task { @MainActor in
            completedEvents += 1
            if let error { status("download失敗 events=\(completedEvents): \(error)") }
            else if let saved = downloadedLocations.removeValue(forKey: task.taskIdentifier) {
                status("download保存 events=\(completedEvents): \(saved.lastPathComponent)")
            } else { status("download完了だが保存先なし events=\(completedEvents)") }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let finished = events
            events = nil
            status("全delegate event完了・host completion解放")
            finished?.finish()
        }
    }
}

private enum P2BackgroundConnectionFailure: Error { case released }

private struct P2BackgroundProbeView: View {
    @ObservedObject var feature: P2BackgroundFeature
    @State private var downloadURL = ""
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.background.\(feature.id.rawValue).status")
            Text("進捗 \(feature.progress)/60 成果 \(feature.resultCount) 世代 \(feature.generation)")
            Button("継続処理を開始") { feature.submitContinued() }
            Button("継続処理を取消") { Task { await feature.cancelContinued() } }
            Divider()
            Text(feature.ordinaryStatus); Button("通常refresh/processingを受付") { feature.submitOrdinary() }
            Text(feature.sharedStatus); Button("共有refreshをjournal受付") { feature.submitSharedRefresh() }
            Button("journal状態を再読込") { feature.refreshSharedJournalStatus() }
            Divider()
            TextField("診断HTTP URL", text: $downloadURL).textInputAutocapitalization(.never)
            Text(feature.transferStatus).textSelection(.enabled)
            Button("background download開始") { feature.startDownload(urlText: downloadURL) }
        }
    }
}
#endif
