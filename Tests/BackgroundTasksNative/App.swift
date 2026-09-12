import BackgroundTasks
import JibunKitCore
import SwiftUI
import UIKit

private enum FixtureIDs {
    static let wrapperA = "com.jibunkit.backgroundtasks-native.owner-a.refresh"
    static let wrapperB = "com.jibunkit.backgroundtasks-native.owner-b.processing"
    static let nativeA = "com.jibunkit.backgroundtasks-native.baseline-a.refresh"
    static let nativeB = "com.jibunkit.backgroundtasks-native.baseline-b.processing"
    static let shared = "com.jibunkit.backgroundtasks-native.shared.refresh"
    static let all = [wrapperA, wrapperB, nativeA, nativeB]
}

@MainActor
private enum FixtureHost {
    static let center = MiniAppBackgroundTaskCenter()
    static let a = center.tasks(for: MiniAppContext(id: MiniAppID("backgroundtasks-a")))
    static let b = center.tasks(for: MiniAppContext(id: MiniAppID("backgroundtasks-b")))
    static var sharedCenter: MiniAppSharedRefreshCenter!
    static var sharedA: MiniAppSharedRefresh!
    static var sharedB: MiniAppSharedRefresh!
    static var sharedStartupResult: MiniAppSharedRefreshSchedulingResult?

    static let definitions = [
        MiniAppDefinition(
            id: MiniAppID("backgroundtasks-a"),
            title: "Background A",
            systemImage: "a.circle",
            onHostLaunch: {
                try a.register(identifier: FixtureIDs.wrapperA, kind: .appRefresh) {
                    $0.complete(success: true)
                }
            },
            makeRootView: { _ in EmptyView() }
        ),
        MiniAppDefinition(
            id: MiniAppID("backgroundtasks-b"),
            title: "Background B",
            systemImage: "b.circle",
            onHostLaunch: {
                try b.register(identifier: FixtureIDs.wrapperB, kind: .processing) {
                    $0.complete(success: true)
                }
            },
            makeRootView: { _ in EmptyView() }
        ),
    ]

    static func registerAtLaunch() throws {
        for identifier in FixtureIDs.all {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        for definition in definitions { try definition.onHostLaunch?() }
        guard BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FixtureIDs.nativeA,
            using: .main,
            launchHandler: { $0.setTaskCompleted(success: true) }
        ) else { throw ProbeFailure.registrationRejected(FixtureIDs.nativeA) }
        guard BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FixtureIDs.nativeB,
            using: .main,
            launchHandler: { $0.setTaskCompleted(success: true) }
        ) else { throw ProbeFailure.registrationRejected(FixtureIDs.nativeB) }

        let center = try MiniAppSharedRefreshCenter(
            identifier: FixtureIDs.shared,
            journalURL: SharedRefreshFixtureStorage.journalURL
        )
        let a = center.refreshes(for: MiniAppContext(id: MiniAppID("shared-refresh-a")))
        let b = center.refreshes(for: MiniAppContext(id: MiniAppID("shared-refresh-b")))
        try a.register(identifier: "sync") { execution in
            SharedRefreshFixtureStorage.recordLaunch(owner: "a", execution: execution)
        }
        try b.register(identifier: "sync") { execution in
            SharedRefreshFixtureStorage.recordLaunch(owner: "b", execution: execution)
        }
        sharedCenter = center
        sharedA = a
        sharedB = b
        sharedStartupResult = center.reconcile()
    }
}

@MainActor
private final class FixtureAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        do { try FixtureHost.registerAtLaunch() }
        catch { preconditionFailure("BackgroundTasks launch registration failed: \(error)") }
        return true
    }
}

@main
private struct BackgroundTasksNativeApp: App {
    @UIApplicationDelegateAdaptor(FixtureAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

@MainActor
private struct ProbeView: View {
    @State private var result = "ready"
    @State private var sharedResult = "shared ready"

    var body: some View {
        VStack {
            Text(result).accessibilityIdentifier("backgroundtasks.result")
            Button("Run native BackgroundTasks comparison") {
                result = "running"
                Task {
                    do { result = try await BackgroundTasksProbe.run() }
                    catch { result = "failed: \(error)" }
                }
            }
            .accessibilityIdentifier("backgroundtasks.run")
            Text(sharedResult).accessibilityIdentifier("backgroundtasks.shared.result")
            Button("Prepare shared refresh persistence") {
                sharedResult = "running"
                Task {
                    do { sharedResult = try await SharedRefreshNativeProbe.prepare() }
                    catch { sharedResult = SharedRefreshNativeProbe.failureDescription(error) }
                }
            }
            .accessibilityIdentifier("backgroundtasks.shared.prepare")
            Button("Verify saved shared refresh") {
                sharedResult = "running"
                Task {
                    do { sharedResult = try await SharedRefreshNativeProbe.verifyAfterRelaunch() }
                    catch { sharedResult = SharedRefreshNativeProbe.failureDescription(error) }
                }
            }
            .accessibilityIdentifier("backgroundtasks.shared.verify")
            Button("Clean up shared refresh fixture") {
                do { sharedResult = try SharedRefreshNativeProbe.cleanup() }
                catch { sharedResult = SharedRefreshNativeProbe.failureDescription(error) }
            }
            .accessibilityIdentifier("backgroundtasks.shared.cleanup")
        }
    }
}

private enum ProbeFailure: Error {
    case registrationRejected(String)
    case missingRequest(String)
    case wrongKind(String)
    case wrongConditions(String)
    case wrongEarliestDate(String)
    case cancellationNotScoped([String])
    case submissionRejected(wrapper: SchedulerError?, native: SchedulerError?)
    case sharedNotReady
    case sharedLogicalState(String)
    case sharedNativeState(String)
    case sharedNativeRejected(stage: String, domain: String, code: Int, durable: String)
    case sharedExpectationMissing
}

private struct SchedulerError: Error, Sendable {
    let domain: String
    let code: Int

    init(_ error: Error) {
        let native = error as NSError
        domain = native.domain
        code = native.code
    }
}

private struct PendingSnapshot: Sendable {
    enum Kind: Equatable, Sendable { case refresh, processing }

    let identifier: String
    let kind: Kind
    let earliestBeginDate: Date?
    let requiresNetworkConnectivity: Bool
    let requiresExternalPower: Bool

    init(_ request: BGTaskRequest) {
        identifier = request.identifier
        earliestBeginDate = request.earliestBeginDate
        if let processing = request as? BGProcessingTaskRequest {
            kind = .processing
            requiresNetworkConnectivity = processing.requiresNetworkConnectivity
            requiresExternalPower = processing.requiresExternalPower
        } else {
            kind = .refresh
            requiresNetworkConnectivity = false
            requiresExternalPower = false
        }
    }
}

private struct SharedRefreshExpectation: Codable, Equatable {
    let generation: UUID
    let earliestBeginDate: Date
}

private struct SharedRefreshLaunchEvidence: Codable {
    let owner: String
    let generation: UUID
    let isRecovery: Bool
    let completion: String
}

@MainActor
private enum SharedRefreshFixtureStorage {
    private static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SharedRefreshNative", isDirectory: true)
    }

    static var journalURL: URL { supportURL.appendingPathComponent("journal.json") }
    static var expectationURL: URL { supportURL.appendingPathComponent("expectation.json") }
    static var launchEvidenceURL: URL { supportURL.appendingPathComponent("launch-evidence.json") }

    static func saveExpectation(_ expectation: SharedRefreshExpectation) throws {
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(expectation).write(to: expectationURL, options: .atomic)
    }

    static func loadExpectation() throws -> SharedRefreshExpectation {
        guard FileManager.default.fileExists(atPath: expectationURL.path) else {
            throw ProbeFailure.sharedExpectationMissing
        }
        return try JSONDecoder().decode(
            SharedRefreshExpectation.self,
            from: Data(contentsOf: expectationURL)
        )
    }

    static func recordLaunch(owner: String, execution: MiniAppSharedRefreshExecution) {
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let existing = (try? JSONDecoder().decode(
                [SharedRefreshLaunchEvidence].self,
                from: Data(contentsOf: launchEvidenceURL)
            )) ?? []
            let evidence = SharedRefreshLaunchEvidence(
                owner: owner,
                generation: execution.request.generation,
                isRecovery: execution.request.isRecovery,
                completion: describe(execution.complete(success: true))
            )
            try JSONEncoder().encode(existing + [evidence])
                .write(to: launchEvidenceURL, options: .atomic)
        } catch {
            _ = execution.complete(success: false)
            let native = error as NSError
            let fallback = "evidence-failed:\(native.domain):\(native.code)"
            try? Data(fallback.utf8).write(to: launchEvidenceURL, options: .atomic)
        }
    }

    static func launchEvidenceDescription() -> String {
        guard let data = try? Data(contentsOf: launchEvidenceURL),
              let evidence = try? JSONDecoder().decode([SharedRefreshLaunchEvidence].self, from: data)
        else { return "none" }
        return evidence.map {
            "\($0.owner):\($0.generation.uuidString):recovery=\($0.isRecovery):\($0.completion)"
        }.joined(separator: ",")
    }

    static func removeFixtureState() throws {
        for url in [expectationURL, launchEvidenceURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func describe(_ completion: MiniAppSharedRefreshCompletion) -> String {
        switch completion {
        case .recorded: return "recorded"
        case .alreadyCompleted: return "already-completed"
        case let .acknowledgementFailed(error):
            let native = error as NSError
            return "ack-failed:\(native.domain):\(native.code)"
        }
    }
}

@MainActor
private enum SharedRefreshNativeProbe {
    static func prepare() async throws -> String {
        let (_, a, b) = try handles()
        _ = try a.cancelAllPendingRequests()
        _ = try b.cancelAllPendingRequests()
        try SharedRefreshFixtureStorage.removeFixtureState()

        let base = Date()
        let aDate = base.addingTimeInterval(3_600)
        let bDate = base.addingTimeInterval(1_800)
        let aReceipt = try a.submit(identifier: "sync", earliestBeginDate: aDate)
        try requireSubmitted(aReceipt.scheduling, stage: "submit-a", earliest: aDate,
                             durable: durableDescription(a: a, b: b))
        let bReceipt = try b.submit(identifier: "sync", earliestBeginDate: bDate)
        try requireSubmitted(bReceipt.scheduling, stage: "submit-b", earliest: bDate,
                             durable: durableDescription(a: a, b: b))
        try requireLogical(a.pendingRequests, generation: aReceipt.generation, date: aDate, owner: "a")
        try requireLogical(b.pendingRequests, generation: bReceipt.generation, date: bDate, owner: "b")
        try await requireOneNativeSharedRequest(earliest: bDate)

        let cancellation = try a.cancel(identifier: "sync")
        try requireSubmitted(cancellation, stage: "cancel-a", earliest: bDate,
                             durable: durableDescription(a: a, b: b))
        guard a.pendingRequests.isEmpty else {
            throw ProbeFailure.sharedLogicalState("a-not-cancelled \(durableDescription(a: a, b: b))")
        }
        try requireLogical(b.pendingRequests, generation: bReceipt.generation, date: bDate, owner: "b")
        try await requireOneNativeSharedRequest(earliest: bDate)
        try SharedRefreshFixtureStorage.saveExpectation(.init(
            generation: bReceipt.generation,
            earliestBeginDate: bDate
        ))
        return "passed: shared prepared saved-a=\(aReceipt.generation.uuidString) native-a=submitted saved-b=\(bReceipt.generation.uuidString) native-b=submitted a-cancelled b-pending native-count=1 earliest=min"
    }

    static func verifyAfterRelaunch() async throws -> String {
        let (_, a, b) = try handles()
        let expectation = try SharedRefreshFixtureStorage.loadExpectation()
        guard a.pendingRequests.isEmpty else {
            throw ProbeFailure.sharedLogicalState("a-restored \(durableDescription(a: a, b: b))")
        }
        try requireLogical(
            b.pendingRequests,
            generation: expectation.generation,
            date: expectation.earliestBeginDate,
            owner: "b"
        )
        if let startup = FixtureHost.sharedStartupResult {
            try requireSubmitted(startup, stage: "startup-reconcile",
                                 earliest: expectation.earliestBeginDate,
                                 durable: durableDescription(a: a, b: b))
        } else {
            throw ProbeFailure.sharedNotReady
        }
        try await requireOneNativeSharedRequest(earliest: expectation.earliestBeginDate)
        return "passed: shared restored b=\(expectation.generation.uuidString) native-count=1 earliest=preserved launch=\(SharedRefreshFixtureStorage.launchEvidenceDescription())"
    }

    static func cleanup() throws -> String {
        let (_, a, b) = try handles()
        _ = try a.cancelAllPendingRequests()
        _ = try b.cancelAllPendingRequests()
        try SharedRefreshFixtureStorage.removeFixtureState()
        return "passed: shared cleanup a=0 b=0"
    }

    static func failureDescription(_ error: Error) -> String {
        if case let ProbeFailure.sharedNativeRejected(stage, domain, code, durable) = error {
            return "failed: shared native rejected stage=\(stage) domain=\(domain) code=\(code) durable=\(durable)"
        }
        let native = error as NSError
        return "failed: shared \(error) domain=\(native.domain) code=\(native.code) durable=\(currentDurableDescription()) launch=\(SharedRefreshFixtureStorage.launchEvidenceDescription())"
    }

    private static func handles() throws -> (
        MiniAppSharedRefreshCenter, MiniAppSharedRefresh, MiniAppSharedRefresh
    ) {
        guard let center = FixtureHost.sharedCenter,
              let a = FixtureHost.sharedA,
              let b = FixtureHost.sharedB
        else { throw ProbeFailure.sharedNotReady }
        return (center, a, b)
    }

    private static func requireSubmitted(
        _ result: MiniAppSharedRefreshSchedulingResult,
        stage: String,
        earliest: Date,
        durable: String
    ) throws {
        switch result {
        case let .submitted(actual, _):
            guard let actual, abs(actual.timeIntervalSince(earliest)) < 2 else {
                throw ProbeFailure.sharedNativeState("\(stage)-wrong-earliest")
            }
        case let .rejected(error, _):
            let native = error as NSError
            throw ProbeFailure.sharedNativeRejected(
                stage: stage,
                domain: native.domain,
                code: native.code,
                durable: durable
            )
        case let .idle(unregistered):
            throw ProbeFailure.sharedNativeState("\(stage)-idle-unregistered=\(unregistered)")
        }
    }

    private static func requireLogical(
        _ requests: [MiniAppSharedRefreshRequest],
        generation: UUID,
        date: Date,
        owner: String
    ) throws {
        guard requests.count == 1,
              requests[0].generation == generation,
              requests[0].identifier == "sync",
              !requests[0].isRecovery,
              requests[0].earliestBeginDate.map({ abs($0.timeIntervalSince(date)) < 2 }) == true
        else { throw ProbeFailure.sharedLogicalState("\(owner)=\(requests)") }
    }

    private static func requireOneNativeSharedRequest(earliest: Date) async throws {
        let all: [PendingSnapshot] = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests.map(PendingSnapshot.init))
            }
        }
        let requests = all.filter { $0.identifier == FixtureIDs.shared }
        guard requests.count == 1 else {
            throw ProbeFailure.sharedNativeState("count=\(requests.count)")
        }
        try BackgroundTasksProbe.verify(
            requests[0], kind: .refresh, earliest: earliest, network: false, power: false
        )
    }

    private static func durableDescription(
        a: MiniAppSharedRefresh,
        b: MiniAppSharedRefresh
    ) -> String {
        "a=[\(a.pendingRequests.map { $0.generation.uuidString }.joined(separator: ","))],b=[\(b.pendingRequests.map { $0.generation.uuidString }.joined(separator: ","))]"
    }

    private static func currentDurableDescription() -> String {
        guard let a = FixtureHost.sharedA, let b = FixtureHost.sharedB else { return "not-ready" }
        return durableDescription(a: a, b: b)
    }
}

@MainActor
private enum BackgroundTasksProbe {
    static func run() async throws -> String {
        let wrapperDate = Date().addingTimeInterval(600)
        let nativeDate = Date().addingTimeInterval(900)

        let nativeError: SchedulerError?
        do {
            try await runNativePhase(earliest: nativeDate)
            nativeError = nil
        } catch {
            guard (error as NSError).domain == "BGTaskSchedulerErrorDomain" else { throw error }
            nativeError = SchedulerError(error)
        }

        let wrapperError: SchedulerError?
        do {
            try await runWrapperPhase(earliest: wrapperDate)
            wrapperError = nil
        } catch {
            guard (error as NSError).domain == "BGTaskSchedulerErrorDomain" else { throw error }
            wrapperError = SchedulerError(error)
        }

        if nativeError != nil || wrapperError != nil {
            throw ProbeFailure.submissionRejected(wrapper: wrapperError, native: nativeError)
        }
        return "passed: wrapper-a=refresh wrapper-b=processing native-a=refresh native-b=processing a-cancelled b-pending"
    }

    private static func runNativePhase(earliest: Date) async throws {
        defer {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: FixtureIDs.nativeA)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: FixtureIDs.nativeB)
        }
        let nativeRefresh = BGAppRefreshTaskRequest(identifier: FixtureIDs.nativeA)
        nativeRefresh.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(nativeRefresh)
        let nativeProcessing = BGProcessingTaskRequest(identifier: FixtureIDs.nativeB)
        nativeProcessing.earliestBeginDate = earliest
        nativeProcessing.requiresNetworkConnectivity = true
        nativeProcessing.requiresExternalPower = true
        try BGTaskScheduler.shared.submit(nativeProcessing)

        let initial = try await pendingByIdentifier()
        try verify(initial[FixtureIDs.nativeA], kind: .refresh,
                   earliest: earliest, network: false, power: false)
        try verify(initial[FixtureIDs.nativeB], kind: .processing,
                   earliest: earliest, network: true, power: true)

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: FixtureIDs.nativeA)
        let remaining = Set(try await pendingByIdentifier().keys)
        guard remaining.contains(FixtureIDs.nativeB), !remaining.contains(FixtureIDs.nativeA) else {
            throw ProbeFailure.cancellationNotScoped(remaining.sorted())
        }
    }

    private static func runWrapperPhase(earliest: Date) async throws {
        defer {
            try? FixtureHost.a.cancel(identifier: FixtureIDs.wrapperA)
            try? FixtureHost.b.cancel(identifier: FixtureIDs.wrapperB)
        }
        try FixtureHost.a.submit(.init(
            identifier: FixtureIDs.wrapperA,
            earliestBeginDate: earliest
        ))
        try FixtureHost.b.submit(.init(
            identifier: FixtureIDs.wrapperB,
            earliestBeginDate: earliest,
            requiresNetworkConnectivity: true,
            requiresExternalPower: true
        ))

        let initial = try await pendingByIdentifier()
        try verify(initial[FixtureIDs.wrapperA], kind: .refresh,
                   earliest: earliest, network: false, power: false)
        try verify(initial[FixtureIDs.wrapperB], kind: .processing,
                   earliest: earliest, network: true, power: true)

        try FixtureHost.a.cancel(identifier: FixtureIDs.wrapperA)
        let remaining = Set(try await pendingByIdentifier().keys)
        guard remaining.contains(FixtureIDs.wrapperB), !remaining.contains(FixtureIDs.wrapperA) else {
            throw ProbeFailure.cancellationNotScoped(remaining.sorted())
        }
    }

    private static func pendingByIdentifier() async throws -> [String: PendingSnapshot] {
        let requests = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests.map(PendingSnapshot.init))
            }
        }
        return Dictionary(uniqueKeysWithValues: requests.map { ($0.identifier, $0) })
    }

    fileprivate static func verify(
        _ request: PendingSnapshot?,
        kind: PendingSnapshot.Kind,
        earliest: Date,
        network: Bool,
        power: Bool
    ) throws {
        guard let request else { throw ProbeFailure.missingRequest(String(describing: kind)) }
        guard request.kind == kind else { throw ProbeFailure.wrongKind(request.identifier) }
        guard let actualDate = request.earliestBeginDate,
              abs(actualDate.timeIntervalSince(earliest)) < 2
        else { throw ProbeFailure.wrongEarliestDate(request.identifier) }
        guard request.requiresNetworkConnectivity == network,
              request.requiresExternalPower == power
        else {
            throw ProbeFailure.wrongConditions(request.identifier)
        }
    }
}
