import AppIntents
import ContinuingFeatureA
import JibunKitCore
import SwiftUI
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self] }
}
@main struct FixtureHost: App {
    @State private var definitions: [MiniAppDefinition] = []
    @State private var errorMessage: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let errorMessage { Text(errorMessage) }
                else { TabView { ForEach(definitions) { definition in
                    definition.makeDestination().tabItem { Text(definition.title) }
                } } }
            }.task {
                guard definitions.isEmpty, errorMessage == nil else { return }
                do {
                    let prepared = try [FeatureALiveIntegration.makeDefinition()]
                    for definition in prepared {
                        try definition.effectiveExternalAccess?.prepare(true)
                        try definition.onHostLaunch?()
                    }
                    definitions = prepared
                } catch { errorMessage = String(describing: error) }
            }
        }
    }
}
