import BackgroundTasks
import JibunKitCore
import SwiftUI
import UIKit

private enum FixtureIDs {
    static let wrapperA = "com.jibunkit.backgroundtasks-native.owner-a.refresh"
    static let wrapperB = "com.jibunkit.backgroundtasks-native.owner-b.processing"
    static let nativeA = "com.jibunkit.backgroundtasks-native.baseline-a.refresh"
    static let nativeB = "com.jibunkit.backgroundtasks-native.baseline-b.processing"
    static let all = [wrapperA, wrapperB, nativeA, nativeB]
}

@MainActor
private enum FixtureHost {
    static let center = MiniAppBackgroundTaskCenter()
    static let a = center.tasks(for: MiniAppContext(id: MiniAppID("backgroundtasks-a")))
    static let b = center.tasks(for: MiniAppContext(id: MiniAppID("backgroundtasks-b")))

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
        BGTaskScheduler.shared.cancelAllTaskRequests()
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

private struct ProbeView: View {
    @State private var result = "ready"

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
}

@MainActor
private enum BackgroundTasksProbe {
    static func run() async throws -> String {
        let wrapperDate = Date().addingTimeInterval(600)
        let nativeDate = Date().addingTimeInterval(900)

        try FixtureHost.a.submit(.init(
            identifier: FixtureIDs.wrapperA,
            earliestBeginDate: wrapperDate
        ))
        try FixtureHost.b.submit(.init(
            identifier: FixtureIDs.wrapperB,
            earliestBeginDate: wrapperDate,
            requiresNetworkConnectivity: true,
            requiresExternalPower: true
        ))

        let nativeRefresh = BGAppRefreshTaskRequest(identifier: FixtureIDs.nativeA)
        nativeRefresh.earliestBeginDate = nativeDate
        try BGTaskScheduler.shared.submit(nativeRefresh)
        let nativeProcessing = BGProcessingTaskRequest(identifier: FixtureIDs.nativeB)
        nativeProcessing.earliestBeginDate = nativeDate
        nativeProcessing.requiresNetworkConnectivity = true
        nativeProcessing.requiresExternalPower = true
        try BGTaskScheduler.shared.submit(nativeProcessing)

        let initial = try await pendingByIdentifier()
        try verify(initial[FixtureIDs.wrapperA], kind: BGAppRefreshTaskRequest.self,
                   earliest: wrapperDate, network: false, power: false)
        try verify(initial[FixtureIDs.wrapperB], kind: BGProcessingTaskRequest.self,
                   earliest: wrapperDate, network: true, power: true)
        try verify(initial[FixtureIDs.nativeA], kind: BGAppRefreshTaskRequest.self,
                   earliest: nativeDate, network: false, power: false)
        try verify(initial[FixtureIDs.nativeB], kind: BGProcessingTaskRequest.self,
                   earliest: nativeDate, network: true, power: true)

        try FixtureHost.a.cancel(identifier: FixtureIDs.wrapperA)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: FixtureIDs.nativeA)
        let afterCancellation = try await pendingByIdentifier()
        let remaining = Set(afterCancellation.keys)
        guard remaining == Set([FixtureIDs.wrapperB, FixtureIDs.nativeB]) else {
            throw ProbeFailure.cancellationNotScoped(remaining.sorted())
        }
        BGTaskScheduler.shared.cancelAllTaskRequests()
        return "passed: wrapper-a=refresh wrapper-b=processing native-a=refresh native-b=processing a-cancelled b-pending"
    }

    private static func pendingByIdentifier() async throws -> [String: BGTaskRequest] {
        let requests = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { continuation.resume(returning: $0) }
        }
        return Dictionary(uniqueKeysWithValues: requests.map { ($0.identifier, $0) })
    }

    private static func verify(
        _ request: BGTaskRequest?,
        kind: BGTaskRequest.Type,
        earliest: Date,
        network: Bool,
        power: Bool
    ) throws {
        guard let request else { throw ProbeFailure.missingRequest(String(describing: kind)) }
        guard type(of: request) == kind else { throw ProbeFailure.wrongKind(request.identifier) }
        guard let actualDate = request.earliestBeginDate,
              abs(actualDate.timeIntervalSince(earliest)) < 2
        else { throw ProbeFailure.wrongEarliestDate(request.identifier) }
        if let processing = request as? BGProcessingTaskRequest {
            guard processing.requiresNetworkConnectivity == network,
                  processing.requiresExternalPower == power
            else { throw ProbeFailure.wrongConditions(request.identifier) }
        } else if network || power {
            throw ProbeFailure.wrongConditions(request.identifier)
        }
    }
}
