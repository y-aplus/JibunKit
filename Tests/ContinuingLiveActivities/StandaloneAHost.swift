import AppIntents
import ContinuingFeatureA
import JibunKitCore
import SwiftUI
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self] } }
@main struct FixtureHost: App {
    @State private var definition: MiniAppDefinition?
    var body: some Scene { WindowGroup { Group { if let definition { definition.makeDestination() } else { ProgressView() } }.task { definition = try? FeatureALiveIntegration.makeDefinition() } } }
}
