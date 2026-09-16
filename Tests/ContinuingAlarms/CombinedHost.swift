import AppIntents
import ContinuingAlarmFeatureA
import ContinuingAlarmFeatureB
import JibunKitCore
import SwiftUI

struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAAlarmIntents.self, FeatureBAlarmIntents.self]
    }
}

@main
@MainActor
struct AlarmCombinedHost: App {
    private let definitions = Result {
        [try FeatureAAlarmIntegration.makeDefinition(), try FeatureBAlarmIntegration.makeDefinition()]
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                switch definitions {
                case .success(let definitions):
                    List(definitions) { definition in
                        NavigationLink(definition.title) { definition.makeDestination() }
                    }
                case .failure(let error): Text("Combined setup failure: \(error)")
                }
            }
        }
    }
}
