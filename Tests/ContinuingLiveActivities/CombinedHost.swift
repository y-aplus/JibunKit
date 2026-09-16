import AppIntents
import ContinuingFeatureA
import ContinuingFeatureB
import SwiftUI
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}
@main struct FixtureHost: App {
    var body: some Scene {
        WindowGroup { TabView { FeatureADiagnosticView().tabItem { Text("A") }; FeatureBDiagnosticView().tabItem { Text("B") } } }
    }
}
