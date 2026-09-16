import AppIntents
import ContinuingAlarmFeatureB
import JibunKitCore
import SwiftUI

struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureBAlarmIntents.self] }
}

@main
@MainActor
struct AlarmStandaloneBHost: App {
    private let definition = Result { try FeatureBAlarmIntegration.makeDefinition() }
    var body: some Scene {
        WindowGroup {
            switch definition {
            case .success(let definition): definition.makeDestination()
            case .failure(let error): Text("B setup failure: \(error)")
            }
        }
    }
}
