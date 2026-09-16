import AppIntents
import ContinuingFeatureA
import ContinuingFeatureB
import JibunKitCore
import SwiftUI
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}
@main struct FixtureHost: App {
    @State private var definitions: [MiniAppDefinition] = []
    var body: some Scene {
        WindowGroup { TabView { ForEach(definitions) { definition in definition.makeDestination().tabItem { Text(definition.title) } } }
            .task { definitions = (try? [FeatureALiveIntegration.makeDefinition(), FeatureBLiveIntegration.makeDefinition()]) ?? [] } }
    }
}
