import AppIntents
import ContinuingAlarmFeatureA
import JibunKitCore
import SwiftUI

struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAAlarmIntents.self] }
}

@main
@MainActor
struct AlarmStandaloneAHost: App {
    private let definition = Result { try FeatureAAlarmIntegration.makeDefinition() }
    var body: some Scene {
        WindowGroup {
            switch definition {
            case .success(let definition): definition.makeDestination()
            case .failure(let error): Text("A setup failure: \(error)")
            }
        }
    }
}
