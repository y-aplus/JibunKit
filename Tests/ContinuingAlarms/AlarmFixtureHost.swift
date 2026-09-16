#if canImport(AlarmKit)
import AppIntents
import JibunKitCore
import SwiftUI

public struct ContinuingAlarmFixtureIntents: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] { [ContinuingAlarmIntents.self] }
}

@main
struct ContinuingAlarmFixtureHost: App {
    @State private var setup = "準備中"
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Text(setup).accessibilityIdentifier("alarm.fixture.status")
                    #if ALARM_FEATURE_A
                    NavigationLink("Feature A") { AlarmDiagnosticViewFactory.featureA() }
                    #endif
                    #if ALARM_FEATURE_B
                    NavigationLink("Feature B") { AlarmDiagnosticViewFactory.featureB() }
                    #endif
                }
                .task { await configure() }
            }
        }
    }

    @MainActor private func configure() async {
        guard setup == "準備中" else { return }
        do {
            let group = try SharedGroupResolver().resolve()
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw MiniAppFileError.unavailableGroupContainer(identifier: group)
            }
            #if ALARM_FEATURE_A
            try await featureAAlarmRuntime.configure(containerURL: container)
            await featureAAlarmRuntime.reconcile()
            #endif
            #if ALARM_FEATURE_B
            try await featureBAlarmRuntime.configure(containerURL: container)
            await featureBAlarmRuntime.reconcile()
            #endif
            setup = "ready（localID: same-id）"
        } catch { setup = "準備失敗: \(error)" }
    }
}
#endif
