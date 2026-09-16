import AppIntents
import ContinuingFeatureB
import JibunKitCore
import SwiftUI
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureBIntents.self] } }
@main struct FixtureHost: App {
    @State private var definition: MiniAppDefinition?
    var body: some Scene { WindowGroup { Group { if let definition { definition.makeDestination() } else { ProgressView() } }.task { definition = try? FeatureBLiveIntegration.makeDefinition() } } }
}
