import AppIntents
import JibunKitCore
import SwiftUI
import InteractiveFeatureA
import InteractiveFeatureB
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}
@main
struct FixtureHost: App {
    @State private var definitions: [MiniAppDefinition] = []
    @State private var management: MiniAppManagement?
    @State private var status = "preparing"
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Text(status).accessibilityIdentifier("interactive.status")
                    ForEach(definitions) { definition in
                        NavigationLink(definition.title) { definition.makeDestination() }
                    }
                }
            }.task {
                guard management == nil else { return }
                do {
                    let defaults = try MiniAppStorage.sharedDefaults()
                    definitions = [
                    FeatureAMiniApp.definition(store: try .shared()),
                    FeatureBMiniApp.definition(store: try .shared())
                    ]
                    management = MiniAppManagement(registrations: definitions.map {
                        .init(id: $0.id, removal: $0.removal, externalAccess: $0.externalAccess)
                    }, defaults: defaults, consents: .init(defaults: defaults))
                    status = "ready"
                } catch { status = "error: \(error)" }
            }
        }
    }
}
